"""A tiny, declarative CRUD engine for the admin panel.

Each resource lists the model, the form fields, the table columns, search fields and
filters. Generic views in views.py render them with Tailwind templates.

Roles: admins (is_staff) see every resource. Turf owners (is_venue_owner) only see
resources that declare `owner_path` (the lookup from the row to its venue owner), only
rows of venues they own, and only the `owner_fields` they may edit (None = read-only).
"""
import copy

from django import forms
from django.db import models

from accounts.models import User
from bookings.models import Booking, Coupon
from core.models import FAQ, Notification, PolicySection, RefundRule, SupportTicket
from play.models import Fixture, Game, Group, GroupMember, Tournament, TournamentTeam
from venues.models import Amenity, Area, BlockedSlot, City, Court, Review, Sport, Venue, VenuePhoto, VenueSport

INPUT = ("w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm text-slate-900 "
         "focus:border-brand focus:ring-2 focus:ring-brand/20 outline-none")


class TailwindFormMixin:
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for name, field in self.fields.items():
            w = field.widget
            if isinstance(w, forms.CheckboxInput):
                w.attrs["class"] = "h-5 w-5 rounded border-slate-300 text-brand focus:ring-brand"
            elif isinstance(w, forms.CheckboxSelectMultiple):
                w.attrs["class"] = "grid grid-cols-2 gap-2 text-sm"
            elif isinstance(w, (forms.ClearableFileInput, forms.FileInput)):
                w.attrs["class"] = "js-image-input block w-full text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-brand-50 file:px-3 file:py-2 file:font-semibold file:text-brand"
                w.attrs["accept"] = "image/*"
            elif isinstance(w, forms.SelectMultiple):
                w.attrs["class"] = INPUT + " min-h-[120px]"
            else:
                w.attrs["class"] = INPUT
            if isinstance(w, forms.Textarea):
                w.attrs.setdefault("rows", 4)
            if isinstance(field, forms.DateField):
                w.input_type = "date"
            if isinstance(field, forms.DateTimeField):
                w.input_type = "datetime-local"
                w.format = "%Y-%m-%dT%H:%M"
            if name.endswith("_color") and isinstance(w, forms.TextInput):
                w.input_type = "color"
                w.attrs["class"] = "h-11 w-24 rounded-xl border border-slate-200 bg-white p-1"


class Resource:
    def __init__(self, slug, model, title, fields, columns, search=(), filters=(), icon="table",
                 section="Catalog", can_create=True, can_delete=True, ordering=None, widgets=None,
                 select_related=(), toggles=(), detail_url=None, help="",
                 owner_path=None, owner_fields=None, owner_toggles=None, owner_can_create=None,
                 owner_can_delete=None, owner_section=None, owner_title=None, owner_help=None):
        self.slug, self.model, self.title = slug, model, title
        self.fields, self.columns, self.search, self.filters = fields, columns, search, filters
        self.icon, self.section = icon, section
        self.can_create, self.can_delete, self.can_edit = can_create, can_delete, True
        self.ordering, self.widgets = ordering, widgets or {}
        self.select_related, self.toggles = select_related, toggles
        self.detail_url, self.help = detail_url, help
        # turf-owner view
        self.owner_path, self.owner_fields = owner_path, owner_fields
        self.owner_toggles = toggles if owner_toggles is None else owner_toggles
        self.owner_can_create = (can_create and owner_fields is not None) if owner_can_create is None else owner_can_create
        self.owner_can_delete = (can_delete and owner_fields is not None) if owner_can_delete is None else owner_can_delete
        self.owner_section, self.owner_title, self.owner_help = owner_section, owner_title, owner_help
        self.user = None  # set on the per-request copy for owners

    # ---------------------------------------------------------------- roles

    def for_user(self, user):
        """The resource as `user` may use it, or None if they may not use it at all."""
        if user.is_staff:
            return self
        if not (user.is_venue_owner and self.owner_path):
            return None
        r = copy.copy(self)
        r.user = user
        r.fields = self.owner_fields or []
        r.can_edit = self.owner_fields is not None
        r.can_create, r.can_delete = self.owner_can_create, self.owner_can_delete
        r.toggles = self.owner_toggles
        r.section = self.owner_section or self.section
        r.title = self.owner_title or self.title
        r.help = self.help if self.owner_help is None else self.owner_help
        return r

    def scope(self, qs):
        """Limit a queryset to rows this (per-request) resource may see."""
        if self.user is None:
            return qs
        return qs.filter(**{self.owner_path: self.user})

    def limit_form(self, form):
        """Owners may only point rows at their own venues/courts."""
        if self.user is None:
            return form
        for name, field in form.fields.items():
            qs = getattr(field, "queryset", None)
            if qs is None:
                continue
            if qs.model is Venue:
                field.queryset = qs.filter(owner=self.user)
            elif qs.model is Court:
                field.queryset = qs.filter(venue__owner=self.user)
        return form

    @property
    def verbose(self):
        return self.model._meta.verbose_name

    def form_class(self):
        widgets = {}
        for f in self.model._meta.get_fields():
            if isinstance(f, models.ManyToManyField) and f.name in self.fields:
                widgets[f.name] = forms.CheckboxSelectMultiple
        widgets.update(self.widgets)
        meta = type("Meta", (), {"model": self.model, "fields": self.fields, "widgets": widgets})
        return type(f"{self.model.__name__}Form", (TailwindFormMixin, forms.ModelForm), {"Meta": meta})

    def filter_choices(self):
        out = []
        for name in self.filters:
            f = self.model._meta.get_field(name)
            if f.choices:
                choices = list(f.choices)
            elif isinstance(f, models.BooleanField):
                choices = [("1", "Yes"), ("0", "No")]
            elif isinstance(f, models.ForeignKey):
                qs = f.related_model.objects.all()
                if self.user is not None and f.related_model is Venue:
                    qs = qs.filter(owner=self.user)
                elif self.user is not None and f.related_model is Court:
                    qs = qs.filter(venue__owner=self.user)
                choices = [(o.pk, str(o)) for o in qs[:200]]
            else:
                continue
            out.append({"name": name, "label": f.verbose_name.title(), "choices": choices})
        return out


def col(path, label=None, kind="text"):
    return {"path": path, "label": label or path.split("__")[-1].replace("_", " ").title(), "kind": kind}


RESOURCES = [
    # ------------------------------------------------ catalog
    Resource("venues", Venue, "Venues",
             ["name", "area", "address", "lat", "lng", "phone", "about", "rules", "surface", "size", "cover",
              "opens_at", "closes_at", "peak_start", "peak_end", "is_fast_filling", "highlight", "amenities",
              "rating", "review_count", "owner", "is_active"],
             [col("cover", "", "image"), col("name"), col("area"), col("price_from", "From ₹", "money"),
              col("rating"), col("is_fast_filling", "Fast filling", "bool"), col("is_active", "Active", "bool")],
             search=["name", "area__name", "address"], filters=["is_active"],
             icon="map-pin", detail_url="dashboard:venue_detail", toggles=["is_active", "is_fast_filling"],
             select_related=["area__city"],
             owner_path="owner", owner_title="My grounds", owner_section="My grounds", owner_can_delete=False,
             owner_toggles=(),
             owner_fields=["name", "area", "address", "lat", "lng", "phone", "about", "rules", "surface", "size",
                           "cover", "opens_at", "closes_at", "peak_start", "peak_end", "highlight", "amenities"],
             owner_help="New grounds stay hidden in the app until the Turflet team approves them."),
    Resource("courts", Court, "Courts", ["venue", "name", "meta", "sports", "order", "is_active"],
             [col("venue"), col("name"), col("meta"), col("is_active", "Active", "bool")],
             search=["name", "venue__name"], filters=["venue", "is_active"], icon="layout-grid", toggles=["is_active"],
             owner_path="venue__owner", owner_section="My grounds",
             owner_fields=["venue", "name", "meta", "sports", "order", "is_active"]),
    Resource("venue-sports", VenueSport, "Sport pricing",
             ["venue", "sport", "meta", "image", "base_price", "peak_surcharge", "max_players"],
             [col("venue"), col("sport"), col("meta"), col("base_price", "Base ₹/hr", "money"),
              col("peak_surcharge", "Peak +₹", "money")],
             search=["venue__name", "sport__name"], filters=["venue", "sport"], icon="tag",
             owner_path="venue__owner", owner_section="My grounds",
             owner_fields=["venue", "sport", "meta", "image", "base_price", "peak_surcharge", "max_players"]),
    Resource("photos", VenuePhoto, "Venue photos", ["venue", "image", "caption", "order"],
             [col("image", "", "image"), col("venue"), col("caption"), col("order")],
             filters=["venue"], icon="image",
             owner_path="venue__owner", owner_section="My grounds", owner_fields=["venue", "image", "caption", "order"]),
    Resource("blocked-slots", BlockedSlot, "Blocked slots", ["venue", "court", "date", "start_hour", "end_hour", "reason"],
             [col("venue"), col("court"), col("date"), col("start_hour", "From"), col("end_hour", "To"), col("reason")],
             filters=["venue"], icon="slash", help="Block maintenance or offline bookings so the app shows them as booked.",
             owner_path="venue__owner", owner_section="My grounds",
             owner_fields=["venue", "court", "date", "start_hour", "end_hour", "reason"]),
    Resource("sports", Sport, "Sports",
             ["name", "fg_color", "bg_color", "image", "match_minutes", "team_size", "scoring", "order", "is_active"],
             [col("image", "", "image"), col("name"), col("fg_color", "Colour", "color"), col("scoring"),
              col("order"), col("is_active", "Active", "bool")], search=["name"], icon="activity", toggles=["is_active"]),
    Resource("amenities", Amenity, "Amenities", ["name", "icon", "fg_color", "bg_color", "order"],
             [col("name"), col("icon"), col("fg_color", "Colour", "color"), col("order")], search=["name"], icon="star"),
    Resource("cities", City, "Cities", ["name", "order", "is_popular"],
             [col("name"), col("order"), col("is_popular", "Popular", "bool")], search=["name"], icon="globe",
             toggles=["is_popular"], section="Locations"),
    Resource("areas", Area, "Areas", ["city", "name", "pincode", "lat", "lng", "order"],
             [col("name"), col("city"), col("pincode"), col("lat"), col("lng")], search=["name", "pincode"],
             filters=["city"], icon="navigation", section="Locations"),
    # ------------------------------------------------ sales
    Resource("bookings", Booking, "Bookings",
             ["status", "payment_status", "date", "start_hour", "duration", "court", "notes"],
             [col("code"), col("user"), col("venue"), col("date"), col("start_hour", "Start"), col("duration", "Hrs"),
              col("total", "Total", "money"), col("status", "Status", "badge"), col("payment_status", "Payment", "badge")],
             search=["code", "user__email", "user__phone", "user__name", "venue__name", "transaction_id"],
             filters=["status", "payment_status", "venue"], icon="calendar", section="Sales", can_create=False,
             can_delete=False, detail_url="dashboard:booking_detail", select_related=["user", "venue", "court"],
             ordering=["-created_at"], owner_path="venue__owner"),
    Resource("coupons", Coupon, "Coupons",
             ["code", "description", "discount_type", "value", "max_discount", "min_amount", "first_booking_only",
              "valid_from", "valid_to", "usage_limit", "per_user_limit", "is_active"],
             [col("code"), col("description"), col("discount_type", "Type"), col("value"),
              col("first_booking_only", "First only", "bool"), col("is_active", "Active", "bool")],
             search=["code"], filters=["is_active"], icon="percent", section="Sales", toggles=["is_active"]),
    Resource("reviews", Review, "Reviews", ["venue", "rating", "comment"],
             [col("venue"), col("user"), col("rating"), col("comment"), col("created_at", "Date", "date")],
             filters=["venue"], icon="message-square", section="Sales", can_create=False,
             owner_path="venue__owner"),
    # ------------------------------------------------ people
    Resource("users", User, "Players & staff",
             ["name", "email", "phone", "address", "handle", "home_area", "show_to_nearby", "notifications_on",
              "slot_alerts_on", "wallet_balance", "is_active", "is_venue_owner", "is_staff"],
             [col("name"), col("email"), col("phone"), col("home_area", "Area"), col("wallet_balance", "Wallet", "money"),
              col("is_venue_owner", "Turf owner", "bool"), col("is_staff", "Admin", "bool"),
              col("is_active", "Active", "bool"), col("date_joined", "Joined", "date")],
             search=["email", "phone", "name", "handle"], filters=["is_active", "is_venue_owner", "is_staff"],
             icon="users", section="People", can_create=False, toggles=["is_active", "is_venue_owner"],
             detail_url="dashboard:user_detail",
             help="Turn on “Turf owner” to let someone manage their own grounds, then set them as the owner on "
                  "those venues. They sign in at /admin-panel/ with an email code."),
    Resource("groups", Group, "Squad groups", ["name", "sport", "area", "image", "created_by"],
             [col("name"), col("sport"), col("area"), col("created_by", "Owner"), col("created_at", "Created", "date")],
             search=["name"], filters=["sport"], icon="users", section="People"),
    Resource("members", GroupMember, "Group members", ["group", "user", "role", "position"],
             [col("group"), col("user"), col("role"), col("position")], filters=["group", "role"], icon="user",
             section="People"),
    Resource("games", Game, "Matches",
             ["name", "sport", "group", "venue", "court", "date", "start_hour", "duration", "per_side", "total_cost",
              "status", "result", "won", "created_by"],
             [col("name"), col("sport"), col("venue"), col("date"), col("start_hour", "Start"),
              col("status", "Status", "badge")], search=["name"], filters=["status", "sport"], icon="zap",
             section="Play"),
    Resource("tournaments", Tournament, "Tournaments",
             ["name", "sport", "host", "format", "team_count", "players_per_team", "entry_fee", "prize_pool", "venue",
              "start_date", "window", "overs", "status", "cover"],
             [col("name"), col("sport"), col("venue"), col("start_date", "Starts"), col("team_count", "Teams"),
              col("entry_fee", "Entry", "money"), col("status", "Status", "badge")],
             search=["name"], filters=["status", "sport"], icon="award", section="Play",
             detail_url="dashboard:tournament_detail"),
    Resource("teams", TournamentTeam, "Tournament teams",
             ["tournament", "name", "captain", "captain_name", "group_label", "paid", "eliminated"],
             [col("tournament"), col("name"), col("captain_name", "Captain"), col("paid", "Paid", "bool"),
              col("eliminated", "Out", "bool")], search=["name"], filters=["tournament", "paid"], icon="flag",
             section="Play", toggles=["paid"]),
    Resource("fixtures", Fixture, "Fixtures",
             ["tournament", "round_name", "label", "team_a", "team_b", "court_label", "scheduled_at", "state",
              "a_runs", "a_wkts", "a_balls", "b_runs", "b_wkts", "b_balls", "winner", "result_text"],
             [col("tournament"), col("round_name", "Round"), col("label"), col("name_a", "Team A"),
              col("name_b", "Team B"), col("state", "State", "badge")],
             filters=["tournament", "state"], icon="list", section="Play", can_create=False),
    # ------------------------------------------------ content
    Resource("faqs", FAQ, "FAQs", ["question", "answer", "order", "is_active"],
             [col("question"), col("order"), col("is_active", "Active", "bool")], search=["question", "answer"],
             icon="circle-help", section="Content", toggles=["is_active"]),
    Resource("refund-rules", RefundRule, "Refund rules", ["min_hours_before", "percent", "title", "subtitle"],
             [col("percent", "Refund %"), col("min_hours_before", "Min hours before"), col("title"), col("subtitle")],
             icon="rotate-ccw", section="Content",
             help="Used by the app's policy page AND by the real refund calculation on cancellation."),
    Resource("policies", PolicySection, "Policy sections", ["kind", "heading", "body", "icon", "color", "order"],
             [col("kind", "Kind", "badge"), col("heading"), col("order")], search=["heading", "body"],
             filters=["kind"], icon="shield", section="Content"),
    Resource("tickets", SupportTicket, "Support tickets", ["status", "reply"],
             [col("id", "#"), col("user"), col("subject"), col("status", "Status", "badge"),
              col("created_at", "Created", "date")], search=["subject", "message", "user__email"],
             filters=["status"], icon="inbox", section="Content", can_create=False),
    Resource("notifications", Notification, "Notifications", ["user", "kind", "title", "body", "is_read"],
             [col("user"), col("kind", "Kind", "badge"), col("title"), col("is_read", "Read", "bool"),
              col("created_at", "Sent", "date")], search=["title", "user__email"], filters=["kind"],
             icon="bell", section="Content"),
]

REGISTRY = {r.slug: r for r in RESOURCES}


def sections(user=None):
    out = {}
    for r in RESOURCES:
        if user is not None:
            r = r.for_user(user)
            if r is None:
                continue
        out.setdefault(r.section, []).append(r)
    return out
