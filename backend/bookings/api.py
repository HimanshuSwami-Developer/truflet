from datetime import date as date_cls, timedelta

from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from core.api import image_url
from venues.models import Venue, VenueSport

from . import services
from .models import Booking
from .services import fmt_hour, fmt_time

Auth = permissions.IsAuthenticated


def time_range_short(b):
    """6 – 8 PM, 11 AM – 1 PM"""
    s, e = b.start_hour, b.end_hour
    same = (s < 12) == (e % 24 < 12) and e != 24
    start = f"{(s % 12) or 12}" if same else fmt_hour(s)
    return f"{start} – {fmt_hour(e)}"


def time_range_long(b):
    s, e = fmt_time(b.start_hour), fmt_time(b.end_hour)
    if s[-2:] == e[-2:]:
        s = s[:-3]
    return f"{s} – {e}"


def countdown(b):
    secs = int((b.start_dt - timezone.now()).total_seconds())
    if secs <= 0:
        return "Playing now"
    h, m = secs // 3600, (secs % 3600) // 60
    if h >= 48:
        return f"In {h // 24} days"
    return f"Starts in {h} hrs {m} min" if h else f"Starts in {m} min"


def _related(b, name):
    try:
        return getattr(b, name)
    except ObjectDoesNotExist:
        return None


def social_payload(request, b):
    """Who this booking is played with, and the viewer's part in it."""
    me = request.user
    og, gg = _related(b, "open_game"), _related(b, "group_game")
    role, my_paid = "host", b.total
    data = {"open_game": None, "group": None}
    if og:
        joined = list(og.active_players().select_related("user"))
        mine = next((p for p in joined if p.user_id == me.id), None)
        if b.user_id != me.id:
            role, my_paid = "player", mine.amount if mine else og.share
        data["open_game"] = {
            "id": og.id, "total_players": og.total_players, "joined_count": 1 + len(joined),
            "spots_left": og.spots_left, "share": og.share,
            "players": [b.user.name or "Host"] + [p.user.name or "Player" for p in joined],
        }
    if gg:
        data["group"] = {"id": gg.group_id, "name": gg.group.name, "member_count": gg.group.memberships.count()}
    data.update({"role": role, "my_paid": my_paid})
    return data


def booking_payload(request, b):
    today = timezone.localdate()
    vs = VenueSport.objects.filter(venue=b.venue, sport=b.sport).first()
    cover = b.venue.cover or (b.venue.photos.first().image if b.venue.photos.exists() else None)
    if b.date == today:
        day_label = f"Today, {b.date:%-d %b}"
    else:
        day_label = f"{b.date:%a, %-d %b}"
    note = ""
    if b.status == "confirmed":
        from core.models import AppConfig
        cfg = AppConfig.get()
        cutoff = b.start_dt - timedelta(hours=cfg.free_cancel_hours)
        note = countdown(b) if b.hours_left < 24 else f"Free cancellation till {timezone.localtime(cutoff):%-d %b, %-I %p}"
    elif b.status == "completed":
        note = "How was the pitch?" if not hasattr(b, "review") else f"Played {b.duration} hr{'s' if b.duration > 1 else ''}"
    elif b.status == "cancelled":
        note = (f"Refunded to {b.get_payment_method_display()} on {b.refunded_at:%-d %b}"
                if b.refund_amount else "Not refundable")
    return {
        "id": b.id,
        "code": b.code,
        "status": b.status,
        "payment_status": b.payment_status,
        "venue": {"id": b.venue_id, "name": b.venue.name, "area": b.venue.area.name, "city": b.venue.area.city.name,
                  "address": b.venue.address, "phone": b.venue.phone, "lat": b.venue.lat, "lng": b.venue.lng,
                  "image": image_url(request, cover)},
        "sport": {"id": b.sport_id, "name": b.sport.name, "fg": b.sport.fg_color, "bg": b.sport.bg_color},
        "court": {"id": b.court_id, "name": b.court.name, "meta": b.court.meta},
        "sport_meta": vs.meta if vs else "",
        "date": b.date.isoformat(),
        "date_label": day_label,
        "date_long": f"{b.date:%a, %-d %b %Y}",
        "start_hour": b.start_hour,
        "duration": b.duration,
        "time_short": time_range_short(b),
        "time_long": time_range_long(b),
        "players": b.players,
        "slot_amount": b.slot_amount,
        "rate": b.slot_amount // b.duration if b.duration else 0,
        "peak_hours": b.peak_hours,
        "convenience_fee": b.convenience_fee,
        "gst": b.gst,
        "coupon": b.coupon.code if b.coupon else None,
        "discount": b.discount,
        "total": b.total,
        "payment_method": b.payment_method,
        "payment_method_label": b.get_payment_method_display() if b.payment_method else "",
        "transaction_id": b.transaction_id,
        "held_until": b.held_until.isoformat() if b.held_until else None,
        "paid_at": timezone.localtime(b.paid_at).strftime("%-d %b, %-I:%M %p") if b.paid_at else None,
        "cancellation_code": b.cancellation_code,
        "refund_amount": b.refund_amount,
        "reschedule_count": b.reschedule_count,
        "can_review": b.status == "completed" and not hasattr(b, "review"),
        "note": note,
        "hours_left": round(b.hours_left, 1),
        "masked_phone": b.user.masked_phone,
        "masked_email": b.user.masked_email,
        "qr_payload": f"TURFLET|{b.code}|{b.venue_id}|{b.court_id}|{b.date.isoformat()}|{b.start_hour}|{b.duration}|{b.payment_status}",
        **social_payload(request, b),
    }


@api_view(["GET", "POST"])
@permission_classes([Auth])
def bookings(request):
    if request.method == "POST":
        d = request.data
        venue = get_object_or_404(Venue, pk=d.get("venue"), is_active=True)
        try:
            day = date_cls.fromisoformat(d.get("date", ""))
            start, duration = int(d.get("start_hour")), int(d.get("duration", 1))
        except (TypeError, ValueError):
            raise ValidationError({"date": "date, start_hour and duration are required."})
        if day < timezone.localdate():
            raise ValidationError({"date": "Pick today or a future date."})
        from community.services import attach_to_hold
        with transaction.atomic():
            b = services.create_hold(request.user, venue, d.get("court"), d.get("sport"), day, start, duration)
            # optional: play with a group, or open the game to strangers
            attach_to_hold(b, request.user, group_id=d.get("group"), open_players=d.get("open_players"))
        return Response(booking_payload(request, b), status=201)

    mine = Q(user=request.user) | Q(open_game__players__user=request.user, open_game__players__status="joined")
    Booking.sync_statuses(Booking.objects.filter(mine).distinct())
    qs = (Booking.objects.filter(mine).distinct()
          .select_related("venue__area__city", "court", "sport", "coupon", "user"))
    tab = request.GET.get("tab", "upcoming")
    counts = {
        "upcoming": qs.filter(status="confirmed").count(),
        "completed": qs.filter(status="completed").count(),
        "cancelled": qs.filter(status="cancelled").count(),
    }
    if tab == "completed":
        qs = qs.filter(status="completed").order_by("-date", "-start_hour")
    elif tab == "cancelled":
        qs = qs.filter(status="cancelled").order_by("-date")
    else:
        qs = qs.filter(status="confirmed").order_by("date", "start_hour")
    return Response({"counts": counts, "items": [booking_payload(request, b) for b in qs]})


def _mine(request, pk):
    return get_object_or_404(Booking.objects.select_related("venue__area__city", "court", "sport", "user"),
                             pk=pk, user=request.user)


@api_view(["GET"])
@permission_classes([Auth])
def booking_detail(request, pk):
    # the host, or a player who joined the open game, can view the ticket
    viewer = Q(user=request.user) | Q(open_game__players__user=request.user, open_game__players__status="joined")
    b = get_object_or_404(Booking.objects.filter(viewer).distinct()
                          .select_related("venue__area__city", "court", "sport", "user"), pk=pk)
    Booking.sync_statuses(Booking.objects.filter(pk=b.pk))
    b.refresh_from_db()
    return Response(booking_payload(request, b))


@api_view(["POST"])
@permission_classes([Auth])
def apply_coupon(request, pk):
    b = services.apply_coupon(_mine(request, pk), request.data.get("code", ""))
    return Response(booking_payload(request, b))


@api_view(["POST"])
@permission_classes([Auth])
def pay(request, pk):
    b = services.pay(_mine(request, pk), request.data.get("method", "upi"), request.data.get("upi_id", ""))
    return Response(booking_payload(request, b))


@api_view(["GET", "POST"])
@permission_classes([Auth])
def cancel(request, pk):
    b = _mine(request, pk)
    if request.method == "GET":
        return Response(services.cancel_quote(b))
    b = services.cancel(b, request.data.get("reason", ""))
    return Response(booking_payload(request, b))


@api_view(["POST"])
@permission_classes([Auth])
def reschedule(request, pk):
    b = _mine(request, pk)
    try:
        day = date_cls.fromisoformat(request.data.get("date", ""))
        start = int(request.data.get("start_hour"))
    except (TypeError, ValueError):
        raise ValidationError({"date": "date and start_hour are required."})
    b = services.reschedule(b, day, start, request.data.get("court"))
    return Response(booking_payload(request, b))


@api_view(["GET"])
def validate_coupon(request):
    from .models import Coupon
    c = Coupon.objects.filter(code=request.GET.get("code", "").strip().upper()).first()
    if not c:
        raise ValidationError({"coupon": "That code is not valid."})
    amount = int(request.GET.get("amount", 0) or 0)
    err = c.validate(request.user if request.user.is_authenticated else None, amount)
    if err:
        raise ValidationError({"coupon": err})
    return Response({"code": c.code, "discount": c.discount_for(amount), "description": c.description})
