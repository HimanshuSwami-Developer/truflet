from datetime import timedelta
from functools import wraps

from django import forms
from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, login, logout
from django.core.paginator import Paginator
from django.db.models import Count, Q, Sum
from django.http import Http404, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST

from accounts.mailer import send_login_code
from accounts.models import EmailOTP, User, normalize_email
from bookings import services as booking_services
from bookings.models import Booking
from core.models import AppConfig, Notification, SupportTicket, notify
from venues.models import Court, Sport, Venue, VenuePhoto, VenueSport

from .crud import REGISTRY, TailwindFormMixin, sections


def panel_required(view):
    """Admins and turf owners. Each view must still scope data with my_venues()/my_bookings()."""
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated or not request.user.can_use_panel:
            return redirect(f"/admin-panel/login/?next={request.path}")
        return view(request, *args, **kwargs)
    return wrapper


def admin_required(view):
    """Platform-wide pages: players, settings, broadcast, tournaments."""
    @wraps(view)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated or not request.user.can_use_panel:
            return redirect(f"/admin-panel/login/?next={request.path}")
        if not request.user.is_staff:
            raise Http404
        return view(request, *args, **kwargs)
    return wrapper


def my_venues(user):
    return Venue.objects.all() if user.is_staff else Venue.objects.filter(owner=user)


def my_bookings(user):
    return Booking.objects.all() if user.is_staff else Booking.objects.filter(venue__owner=user)


def ctx(request, **extra):
    admin = request.user.is_staff
    base = {
        "nav": sections(request.user),
        "is_admin": admin,
        "open_tickets": SupportTicket.objects.filter(status="open").count() if admin else 0,
        "path": request.path,
    }
    base.update(extra)
    return base


def is_ajax(request):
    return request.headers.get("x-requested-with") == "XMLHttpRequest"


# ------------------------------------------------------------------ auth

def _safe_next(request):
    nxt = request.GET.get("next") or ""
    return nxt if nxt.startswith("/admin-panel/") else "dashboard:home"


def login_view(request):
    if request.user.is_authenticated and request.user.can_use_panel:
        return redirect("dashboard:home")
    error = None
    if request.method == "POST":
        user = authenticate(request, email=normalize_email(request.POST.get("email", "")),
                            password=request.POST.get("password", ""))
        if user and user.can_use_panel:
            login(request, user)
            return redirect(_safe_next(request))
        error = "Wrong email or password, or this account has no panel access."
    return render(request, "dashboard/login.html", {"error": error})


def login_code_view(request):
    """Email-code sign-in, so turf owners never need a password."""
    if request.user.is_authenticated and request.user.can_use_panel:
        return redirect("dashboard:home")
    email = normalize_email(request.POST.get("email", ""))
    step, error, dev_code = "email", None, None
    if request.method == "POST" and request.POST.get("step") == "send":
        user = User.objects.filter(email=email).first()
        step = "code"
        if EmailOTP.recently_sent(email):
            error = "A code was just sent. Wait 30 seconds before asking again."
        elif user and user.can_use_panel:
            code = EmailOTP.issue(email, dev_mode=settings.OTP_DEV_MODE)
            try:
                send_login_code(email, code)
            except Exception:
                if not settings.OTP_DEV_MODE:
                    step, error = "email", "We couldn't send the email right now. Try again."
            if settings.OTP_DEV_MODE:
                dev_code = code
        # Same answer whether or not the email has access, so the form can't be used to probe accounts.
    elif request.method == "POST" and request.POST.get("step") == "verify":
        step = "code"
        code = request.POST.get("code", "").strip()
        otp = EmailOTP.objects.filter(email=email, used=False).first()
        user = User.objects.filter(email=email).first()
        if not otp or otp.is_expired():
            error = "Code expired. Request a new one."
        elif otp.attempts >= EmailOTP.MAX_ATTEMPTS:
            error = "Too many attempts. Request a new code."
        elif EmailOTP.hash(code) != otp.code_hash:
            otp.attempts += 1
            otp.save(update_fields=["attempts"])
            error = "That code is incorrect."
        elif not (user and user.can_use_panel):
            error = "This account has no panel access. Ask the Turflet team to make you a turf owner."
        else:
            otp.used = True
            otp.save(update_fields=["used"])
            login(request, user, backend="django.contrib.auth.backends.ModelBackend")
            return redirect(_safe_next(request))
    return render(request, "dashboard/login_code.html",
                  {"step": step, "email": email, "error": error, "dev_code": dev_code})


def logout_view(request):
    logout(request)
    return redirect("dashboard:login")


# ------------------------------------------------------------------ home

@panel_required
def home(request):
    Booking.sync_statuses()
    user = request.user
    venues, bookings = my_venues(user), my_bookings(user)
    today = timezone.localdate()
    paid = bookings.filter(payment_status__in=["paid", "refunded"])
    month_start = today.replace(day=1)
    days = []
    for i in range(13, -1, -1):
        d = today - timedelta(days=i)
        amt = paid.filter(paid_at__date=d).aggregate(s=Sum("total"))["s"] or 0
        days.append({"label": d.strftime("%d %b"), "short": d.strftime("%a")[0], "amount": amt})
    peak = max([d["amount"] for d in days] + [1])
    for d in days:
        d["pct"] = round(d["amount"] * 100 / peak)
    top_venues = (venues.annotate(n=Count("bookings", filter=Q(bookings__payment_status="paid")),
                                         rev=Sum("bookings__total", filter=Q(bookings__payment_status="paid")))
                  .order_by("-rev")[:5])
    stats = {
        "today_bookings": bookings.filter(date=today, status__in=["confirmed", "completed"]).count(),
        "today_checked_in": bookings.filter(date=today, checked_in_at__isnull=False).count(),
        "month_revenue": paid.filter(paid_at__date__gte=month_start).aggregate(s=Sum("total"))["s"] or 0,
        "refunds": bookings.filter(refunded_at__date__gte=month_start).aggregate(s=Sum("refund_amount"))["s"] or 0,
        "venues": venues.filter(is_active=True).count(),
        "pending_venues": venues.filter(is_active=False, owner__isnull=False).count(),
        "upcoming_bookings": bookings.filter(date__gt=today, status="confirmed").count(),
    }
    if user.is_staff:
        stats.update({
            "users": User.objects.filter(is_staff=False).count(),
            "new_users": User.objects.filter(date_joined__date__gte=today - timedelta(days=7)).count(),
        })
    return render(request, "dashboard/home.html", ctx(
        request, stats=stats, days=days, top_venues=top_venues,
        upcoming=bookings.filter(date=today, status="confirmed").select_related("user", "venue", "court")
        .order_by("start_hour")[:8],
        recent=bookings.exclude(status__in=["held", "expired"]).select_related("user", "venue")
        .order_by("-created_at")[:8],
    ))


# ------------------------------------------------------------------ generic CRUD

def _resource(slug, user):
    r = REGISTRY.get(slug)
    r = r and r.for_user(user)
    if not r:
        raise Http404
    return r


def _queryset(r, request):
    qs = r.scope(r.model.objects.all())
    if r.select_related:
        qs = qs.select_related(*r.select_related)
    q = request.GET.get("q", "").strip()
    if q and r.search:
        cond = Q()
        for f in r.search:
            cond |= Q(**{f"{f}__icontains": q})
        qs = qs.filter(cond)
    active_filters = {}
    for f in r.filters:
        v = request.GET.get(f)
        if v not in (None, ""):
            field = r.model._meta.get_field(f)
            if field.get_internal_type() == "BooleanField":
                v = v == "1"
            qs = qs.filter(**{f: v})
            active_filters[f] = request.GET.get(f)
    if r.ordering:
        qs = qs.order_by(*r.ordering)
    return qs.distinct(), active_filters


def _limit_form(r, form):
    form = r.limit_form(form)
    owner = form.fields.get("owner")
    if owner is not None:  # admin picking a venue's owner: only turf owners / admins
        owner.queryset = User.objects.filter(Q(is_venue_owner=True) | Q(is_staff=True))
        owner.help_text = "Turf owner who manages this venue (turn on “Turf owner” on the player first)."
    return form


@panel_required
def crud_list(request, slug):
    r = _resource(slug, request.user)
    qs, active = _queryset(r, request)
    page = Paginator(qs, 25).get_page(request.GET.get("page"))
    context = ctx(request, r=r, page=page, filters=r.filter_choices(), active=active, q=request.GET.get("q", ""),
                  total=qs.count())
    if request.GET.get("partial"):
        return render(request, "dashboard/_table.html", context)
    return render(request, "dashboard/crud_list.html", context)


@panel_required
def crud_form(request, slug, pk=None):
    r = _resource(slug, request.user)
    obj = get_object_or_404(r.scope(r.model.objects.all()), pk=pk) if pk else None
    if (obj is None and not r.can_create) or (obj is not None and not r.can_edit):
        raise Http404
    Form = r.form_class()
    owner_new_venue = r.model is Venue and obj is None and not request.user.is_staff
    if request.method == "POST":
        form = _limit_form(r, Form(request.POST, request.FILES, instance=obj))
        if form.is_valid():
            saved = form.save(commit=False)
            if owner_new_venue:
                # Owner-onboarded grounds stay hidden in the app until an admin approves them.
                saved.owner, saved.is_active = request.user, False
            saved.save()
            form.save_m2m()
            if owner_new_venue:
                messages.success(request, "Ground added. Add courts, sports & pricing and photos — the Turflet team "
                                          "will approve it and it goes live in the app.")
                return redirect("dashboard:venue_detail", pk=saved.pk)
            messages.success(request, f"{r.verbose.title()} saved.")
            if request.GET.get("next"):
                return redirect(request.GET["next"])
            if r.detail_url:
                return redirect(r.detail_url, pk=saved.pk)
            return redirect("dashboard:crud_list", slug=slug)
    else:
        initial = {k: v for k, v in request.GET.items() if k in r.fields}
        form = _limit_form(r, Form(instance=obj, initial=initial))
    return render(request, "dashboard/crud_form.html", ctx(request, r=r, form=form, obj=obj))


@panel_required
@require_POST
def crud_delete(request, slug, pk):
    r = _resource(slug, request.user)
    if not r.can_delete:
        return JsonResponse({"ok": False, "message": "Delete is disabled for this resource."}, status=400)
    obj = get_object_or_404(r.scope(r.model.objects.all()), pk=pk)
    try:
        obj.delete()
    except Exception as e:  # ProtectedError etc.
        return JsonResponse({"ok": False, "message": f"Cannot delete: {e.__class__.__name__}. It is still in use."},
                            status=400)
    return JsonResponse({"ok": True})


@panel_required
@require_POST
def crud_toggle(request, slug, pk, field):
    r = _resource(slug, request.user)
    if field not in r.toggles:
        return JsonResponse({"ok": False}, status=400)
    obj = get_object_or_404(r.scope(r.model.objects.all()), pk=pk)
    setattr(obj, field, not getattr(obj, field))
    obj.save(update_fields=[field])
    return JsonResponse({"ok": True, "value": getattr(obj, field)})


# ------------------------------------------------------------------ venues

@panel_required
def venue_detail(request, pk):
    v = get_object_or_404(my_venues(request.user).select_related("area__city", "owner"), pk=pk)
    return render(request, "dashboard/venue_detail.html", ctx(
        request, v=v, photos=v.photos.all(), courts=v.courts.prefetch_related("sports"),
        venue_sports=v.venue_sports.select_related("sport"),
        bookings=v.bookings.exclude(status__in=["held", "expired"]).select_related("user", "court")
        .order_by("-date", "-start_hour")[:10],
        blocked=v.blocked_slots.filter(date__gte=timezone.localdate())[:10],
    ))


@panel_required
@require_POST
def venue_photo_upload(request, pk):
    v = get_object_or_404(my_venues(request.user), pk=pk)
    files = request.FILES.getlist("images")
    created = []
    start = v.photos.count()
    for i, f in enumerate(files):
        p = VenuePhoto.objects.create(venue=v, image=f, order=start + i)
        created.append({"id": p.id, "url": p.image.url})
    return JsonResponse({"ok": True, "photos": created})


@panel_required
@require_POST
def venue_photo_delete(request, pk, photo_id):
    p = get_object_or_404(VenuePhoto, pk=photo_id, venue__in=my_venues(request.user), venue_id=pk)
    p.image.delete(save=False)
    p.delete()
    return JsonResponse({"ok": True})


@panel_required
def availability_board(request, pk):
    """Day view of every court's slots, for the venue desk."""
    v = get_object_or_404(my_venues(request.user), pk=pk)
    try:
        day = timezone.datetime.fromisoformat(request.GET.get("date", "")).date()
    except ValueError:
        day = timezone.localdate()
    rows = []
    hours = list(range(v.opens_at, v.closes_at))
    for court in v.courts.filter(is_active=True):
        bookings = {}
        for b in Booking.objects.filter(court=court, date=day, status__in=["confirmed", "completed", "held"]):
            for h in range(b.start_hour, b.end_hour):
                bookings[h] = b
        taken = booking_services.taken_hours(court, day)
        cells = []
        for h in hours:
            b = bookings.get(h)
            cells.append({"hour": h, "booking": b, "blocked": h in taken and not b})
        rows.append({"court": court, "cells": cells})
    return render(request, "dashboard/availability.html", ctx(
        request, v=v, day=day, hours=hours, rows=rows,
        prev=(day - timedelta(days=1)).isoformat(), next=(day + timedelta(days=1)).isoformat()))


# ------------------------------------------------------------------ bookings

@panel_required
def booking_detail(request, pk):
    b = get_object_or_404(my_bookings(request.user).select_related("user", "venue__area__city", "court", "sport",
                                                                    "coupon"), pk=pk)
    return render(request, "dashboard/booking_detail.html", ctx(
        request, b=b, quote=booking_services.cancel_quote(b) if b.status == "confirmed" else None))


@panel_required
@require_POST
def booking_action(request, pk, action):
    b = get_object_or_404(my_bookings(request.user), pk=pk)
    try:
        if action == "checkin":
            if b.status != "confirmed":
                raise ValueError("Only confirmed bookings can be checked in.")
            b.checked_in_at = timezone.now()
            b.save(update_fields=["checked_in_at"])
            msg = "Checked in."
        elif action == "cancel":
            booking_services.cancel(b, request.POST.get("reason", "Cancelled by venue"), by_venue=True)
            msg = "Cancelled with full refund."
        elif action == "complete":
            b.status = "completed"
            b.save(update_fields=["status"])
            msg = "Marked completed."
        elif action == "notes":
            b.notes = request.POST.get("notes", "")
            b.save(update_fields=["notes"])
            msg = "Notes saved."
        else:
            raise ValueError("Unknown action")
    except Exception as e:
        detail = getattr(e, "detail", None)
        text = str(list(detail.values())[0][0]) if isinstance(detail, dict) else str(e)
        if is_ajax(request):
            return JsonResponse({"ok": False, "message": text}, status=400)
        messages.error(request, text)
        return redirect("dashboard:booking_detail", pk=pk)
    if is_ajax(request):
        return JsonResponse({"ok": True, "message": msg})
    messages.success(request, msg)
    return redirect("dashboard:booking_detail", pk=pk)


@panel_required
def checkin(request):
    """Scan / type a booking code (or the full QR payload) to verify a ticket."""
    code = request.GET.get("code", "").strip()
    booking = None
    if code:
        if code.startswith(("TURFLET|", "TURFLY|")):  # TURFLY| = tickets issued before the rename
            code = code.split("|")[1]
        booking = (my_bookings(request.user).select_related("user", "venue", "court", "sport")
                   .filter(code__iexact=code).first())
        if not booking:
            messages.error(request, f"No booking found for {code}.")
    return render(request, "dashboard/checkin.html", ctx(request, code=code, b=booking,
                                                          today=timezone.localdate()))


# ------------------------------------------------------------------ users

@admin_required
def user_detail(request, pk):
    u = get_object_or_404(User, pk=pk)
    return render(request, "dashboard/user_detail.html", ctx(
        request, u=u, bookings=u.bookings.select_related("venue").order_by("-created_at")[:20],
        spent=u.bookings.filter(payment_status="paid").aggregate(s=Sum("total"))["s"] or 0,
        sports=u.sports.select_related("sport")))


@admin_required
@require_POST
def user_wallet(request, pk):
    u = get_object_or_404(User, pk=pk)
    try:
        delta = int(request.POST.get("amount", 0))
    except ValueError:
        delta = 0
    u.wallet_balance = max(0, u.wallet_balance + delta)
    u.save(update_fields=["wallet_balance"])
    if delta:
        notify(u, "Wallet updated", f"₹{abs(delta)} {'added to' if delta > 0 else 'removed from'} your Turflet balance")
    return JsonResponse({"ok": True, "balance": u.wallet_balance})


# ------------------------------------------------------------------ settings & broadcast

class SettingsForm(TailwindFormMixin, forms.ModelForm):
    class Meta:
        model = AppConfig
        fields = "__all__"


@admin_required
def settings_view(request):
    cfg = AppConfig.get()
    form = SettingsForm(request.POST or None, request.FILES or None, instance=cfg)
    if request.method == "POST" and form.is_valid():
        form.save()
        messages.success(request, "Settings saved.")
        return redirect("dashboard:settings")
    return render(request, "dashboard/settings.html", ctx(request, form=form))


@admin_required
def broadcast(request):
    if request.method == "POST":
        title = request.POST.get("title", "").strip()
        body = request.POST.get("body", "").strip()
        audience = request.POST.get("audience", "all")
        if not title:
            messages.error(request, "Title is required.")
        else:
            users = User.objects.filter(is_active=True, notifications_on=True)
            if audience == "bookers":
                users = users.filter(bookings__payment_status="paid").distinct()
            Notification.objects.bulk_create([Notification(user=u, title=title, body=body, kind="offer") for u in users])
            messages.success(request, f"Sent to {users.count()} players.")
            return redirect("dashboard:broadcast")
    return render(request, "dashboard/broadcast.html", ctx(request))


@panel_required
def api_search(request):
    """Global search box (jQuery autocomplete)."""
    q = request.GET.get("q", "").strip()
    out = []
    if len(q) >= 2:
        for b in my_bookings(request.user).filter(Q(code__icontains=q) | Q(user__email__icontains=q))[:5]:
            out.append({"label": f"{b.code} · {b.venue}", "kind": "Booking", "url": f"/admin-panel/bookings/{b.pk}/"})
        for v in my_venues(request.user).filter(name__icontains=q)[:5]:
            out.append({"label": v.name, "kind": "Venue", "url": f"/admin-panel/venues/{v.pk}/"})
        if not request.user.is_staff:
            return JsonResponse({"results": out})
        for u in User.objects.filter(Q(name__icontains=q) | Q(email__icontains=q) | Q(phone__icontains=q))[:5]:
            out.append({"label": f"{u.name or '—'} · {u.email}", "kind": "Player", "url": f"/admin-panel/users/{u.pk}/"})
    return JsonResponse({"results": out})
