from datetime import date as date_cls

from django.db.models import Count, Q
from django.shortcuts import get_object_or_404
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from bookings.services import slot_grid
from core.api import image_url

from .models import Area, City, Court, Review, SavedVenue, Sport, Venue, VenueSport


def sport_payload(request, s):
    return {"id": s.id, "name": s.name, "slug": s.slug, "fg": s.fg_color, "bg": s.bg_color,
            "image": image_url(request, s.image)}


def _coords(request):
    try:
        return float(request.GET["lat"]), float(request.GET["lng"])
    except (KeyError, ValueError):
        user = request.user if request.user.is_authenticated else None
        if user and user.lat is not None:
            return user.lat, user.lng
        area_id = request.GET.get("area")
        area = Area.objects.filter(pk=area_id).first() if area_id else None
        if area and area.lat is not None:
            return area.lat, area.lng
    return None, None


def venue_card(request, v, lat=None, lng=None, saved_ids=frozenset(), lobby_counts=None):
    sports = [vs.sport for vs in v.venue_sports.all()]
    cover = v.cover or (v.photos.all()[0].image if v.photos.all() else None)
    return {
        "id": v.id,
        "slug": v.slug,
        "name": v.name,
        "area": v.area.name,
        "city": v.area.city.name,
        "distance_km": v.distance_km(lat, lng),
        "rating": float(v.rating),
        "review_count": v.review_count,
        "price_from": v.price_from,
        "sports": [{"id": s.id, "name": s.name, "fg": s.fg_color, "bg": s.bg_color} for s in sports],
        "highlight": v.highlight,
        "is_fast_filling": v.is_fast_filling,
        "image": image_url(request, cover),
        "is_saved": v.id in saved_ids,
        "open_lobbies": (lobby_counts or {}).get(v.id, 0),
        "amenity_icons": [a.icon for a in v.amenities.all()],
    }


def _saved_ids(request):
    if request.user.is_authenticated:
        return set(request.user.saved_venues.values_list("venue_id", flat=True))
    return set()


@api_view(["GET"])
def cities(request):
    data = []
    for c in City.objects.prefetch_related("areas").all():
        counts = dict(Venue.objects.filter(is_active=True, area__city=c).values_list("area").annotate(n=Count("id")))
        data.append({
            "id": c.id, "name": c.name, "is_popular": c.is_popular, "is_live": c.is_live,
            "areas": [{"id": a.id, "name": a.name, "pincode": a.pincode, "lat": a.lat, "lng": a.lng,
                       "venue_count": counts.get(a.id, 0)} for a in c.areas.all()],
        })
    return Response(data)


@api_view(["GET"])
def locate(request):
    """Nearest area for GPS coordinates, among cities that are live in the app."""
    try:
        lat, lng = float(request.GET["lat"]), float(request.GET["lng"])
    except (KeyError, ValueError):
        raise ValidationError({"lat": "lat and lng are required"})
    best, best_d = None, None
    for a in Area.objects.select_related("city").filter(city__is_live=True).exclude(lat__isnull=True):
        d = (a.lat - lat) ** 2 + (a.lng - lng) ** 2
        if best_d is None or d < best_d:
            best, best_d = a, d
    if not best:
        raise ValidationError({"area": "No areas configured yet."})
    return Response({"area_id": best.id, "area": best.name, "city_id": best.city_id, "city": best.city.name})


@api_view(["GET"])
def sports(request):
    return Response([sport_payload(request, s) for s in Sport.objects.filter(is_active=True)])


RADII_KM = (3, 5, 10)
MIN_VENUES = 3  # widen the radius until at least this many arenas show


def _int_param(p, key):
    try:
        return int(p[key])
    except (KeyError, TypeError, ValueError):
        return None


def _free_in_window(venues, day, from_hour, to_hour, sport_id=None):
    """Ids of venues with at least one free court-hour in [from_hour, to_hour) on `day`."""
    from django.utils import timezone

    from bookings.models import Booking
    from .models import BlockedSlot
    ids = [v.id for v in venues]
    now = timezone.now()
    today, now_hour = timezone.localdate(), timezone.localtime().hour
    taken = {}  # court_id -> set(hours)
    for b in (Booking.objects.filter(venue_id__in=ids, date=day)
              .filter(Q(status="confirmed") | Q(status="held", held_until__gt=now))
              .only("court_id", "start_hour", "duration")):
        taken.setdefault(b.court_id, set()).update(range(b.start_hour, b.start_hour + b.duration))
    blocked = {}  # venue_id -> [(court_id|None, start, end)]
    for blk in BlockedSlot.objects.filter(venue_id__in=ids, date=day):
        blocked.setdefault(blk.venue_id, []).append((blk.court_id, blk.start_hour, blk.end_hour))
    courts = Court.objects.filter(venue_id__in=ids, is_active=True).prefetch_related("sports")
    by_venue = {}
    for c in courts:
        if sport_id and not any(str(s.id) == str(sport_id) for s in c.sports.all()):
            continue
        by_venue.setdefault(c.venue_id, []).append(c)
    ok = set()
    for v in venues:
        lo, hi = max(from_hour, v.opens_at), min(to_hour, v.closes_at)
        if day == today:
            lo = max(lo, now_hour + 1)
        for c in by_venue.get(v.id, []):
            busy = set(taken.get(c.id, ()))
            for court_id, s, e in blocked.get(v.id, []):
                if court_id in (None, c.id):
                    busy.update(range(s, e))
            if any(h not in busy for h in range(lo, hi)):
                ok.add(v.id)
                break
    return ok


@api_view(["GET"])
def venue_list(request):
    """Home / Discovery. Filters: sport, q, amenities (icon keys, comma separated), price_min, price_max,
    date + from_hour + to_hour (free slot in that window). Results start within 3 km and widen
    3 → 5 → 10 km → city-wide until at least 3 arenas show."""
    from community.services import open_lobby_counts
    qs = (Venue.objects.filter(is_active=True)
          .select_related("area__city").prefetch_related("venue_sports__sport", "photos", "amenities"))
    p = request.GET
    city_name = ""
    if p.get("city"):
        qs = qs.filter(area__city_id=p["city"])
    elif p.get("area"):
        area = Area.objects.filter(pk=p["area"]).select_related("city").first()
        if area:
            qs = qs.filter(area__city_id=area.city_id)
            city_name = area.city.name
    if p.get("sport"):
        qs = qs.filter(venue_sports__sport_id=p["sport"])
    if p.get("q"):
        q = p["q"]
        qs = qs.filter(Q(name__icontains=q) | Q(area__name__icontains=q) | Q(venue_sports__sport__name__icontains=q))
    if p.get("saved") and request.user.is_authenticated:
        qs = qs.filter(saved_by__user=request.user)
    for icon in [a for a in p.get("amenities", "").split(",") if a]:
        qs = qs.filter(amenities__icon=icon)
    venues = list(qs.distinct())

    price_min, price_max = _int_param(p, "price_min"), _int_param(p, "price_max")
    if price_min is not None or price_max is not None:
        def price(v):
            prices = [vs.base_price for vs in v.venue_sports.all()
                      if not p.get("sport") or str(vs.sport_id) == str(p["sport"])]
            return min(prices) if prices else 0
        venues = [v for v in venues if (price_min is None or price(v) >= price_min)
                  and (price_max is None or price(v) <= price_max)]
    if p.get("date"):
        try:
            day = date_cls.fromisoformat(p["date"])
        except ValueError:
            raise ValidationError({"date": "Use YYYY-MM-DD."})
        from_hour = _int_param(p, "from_hour") or 0
        to_hour = _int_param(p, "to_hour") or 24
        ok = _free_in_window(venues, day, from_hour, to_hour, p.get("sport"))
        venues = [v for v in venues if v.id in ok]

    lat, lng = _coords(request)
    saved = _saved_ids(request)
    counts = open_lobby_counts([v.id for v in venues])
    items = [venue_card(request, v, lat, lng, saved, counts) for v in venues]

    # zero-dead-end radius: only when browsing nearby (not searching by name)
    radius, notice = None, ""
    if lat is not None and not p.get("q") and not p.get("saved") and p.get("radius") != "city":
        for r in RADII_KM:
            near = [x for x in items if x["distance_km"] is not None and x["distance_km"] <= r]
            if len(near) >= MIN_VENUES:
                radius = r
                items = near
                break
        if radius is None:
            notice = f"Few arenas nearby — showing all of {city_name}" if city_name and items else ""
        elif radius != RADII_KM[0]:
            notice = f"Expanded search to {radius} km to show more arenas"

    sort = p.get("sort", "near")
    if sort == "price":
        items.sort(key=lambda x: x["price_from"])
    elif sort == "rating":
        items.sort(key=lambda x: -x["rating"])
    elif sort == "lobbies":
        items.sort(key=lambda x: -x["open_lobbies"])
    else:
        items.sort(key=lambda x: (x["distance_km"] is None, x["distance_km"] or 0))
    return Response({
        "items": items,
        "radius_km": radius,
        "radius_label": f"Within {radius} km" if radius else ("City-wide" if lat is not None else ""),
        "notice": notice,
    })


@api_view(["GET"])
def amenities(request):
    from .models import Amenity
    return Response([{"name": a.name, "icon": a.icon, "fg": a.fg_color, "bg": a.bg_color} for a in Amenity.objects.all()])


@api_view(["GET"])
def venue_detail(request, pk):
    v = get_object_or_404(Venue.objects.select_related("area__city")
                          .prefetch_related("venue_sports__sport", "photos", "amenities", "courts__sports"),
                          pk=pk, is_active=True)
    lat, lng = _coords(request)
    from community.services import open_lobby_counts
    from core.models import RefundRule
    data = venue_card(request, v, lat, lng, _saved_ids(request), open_lobby_counts([v.id]))
    photos = [image_url(request, ph.image) for ph in v.photos.all()]
    if v.cover:
        photos.insert(0, image_url(request, v.cover))
    data.update({
        "address": v.address, "lat": v.lat, "lng": v.lng, "phone": v.phone,
        "about": v.about, "rules": v.rule_list, "surface": v.surface, "size": v.size,
        "court_count": v.courts.filter(is_active=True).count(),
        "hours_label": v.hours_label, "opens_at": v.opens_at, "closes_at": v.closes_at,
        "peak_start": v.peak_start, "peak_end": v.peak_end,
        "photos": photos,
        "amenities": [{"name": a.name, "icon": a.icon, "fg": a.fg_color, "bg": a.bg_color} for a in v.amenities.all()],
        "venue_sports": [{
            "sport_id": vs.sport_id, "name": vs.sport.name, "meta": vs.meta, "price": vs.base_price,
            "peak_surcharge": vs.peak_surcharge, "max_players": vs.max_players,
            "fg": vs.sport.fg_color, "bg": vs.sport.bg_color,
            "image": image_url(request, vs.image or vs.sport.image),
        } for vs in v.venue_sports.all()],
        "courts": [{"id": c.id, "name": c.name, "meta": c.meta, "sport_ids": [s.id for s in c.sports.all()]}
                   for c in v.courts.filter(is_active=True)],
        "cancellation_policy": [{"title": r.title, "subtitle": r.subtitle, "percent": r.percent}
                                for r in RefundRule.objects.all()],
    })
    return Response(data)


@api_view(["GET"])
def availability(request, pk):
    v = get_object_or_404(Venue, pk=pk, is_active=True)
    try:
        day = date_cls.fromisoformat(request.GET["date"])
        vs = VenueSport.objects.select_related("venue").get(venue=v, sport_id=request.GET["sport"])
        court = Court.objects.get(pk=request.GET["court"], venue=v)
    except (KeyError, ValueError):
        raise ValidationError({"date": "date, sport and court are required"})
    except (VenueSport.DoesNotExist, Court.DoesNotExist):
        raise ValidationError({"court": "Unknown sport or court for this venue"})
    from community.services import lobby_hours
    slots = slot_grid(vs, court, day)
    lobbies = lobby_hours(court, day)
    for s in slots:
        cell = lobbies.get(s["hour"]) if s["status"] != "past" else None
        # Open Lobby: groups recruiting solo players here (doesn't block the calendar unless paid)
        s["lobbies"] = cell["lobbies"] if cell else 0
        s["lobby_spots"] = cell["spots"] if cell else 0
    return Response({"date": day.isoformat(), "court": court.id, "sport": vs.sport_id, "slots": slots})


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def toggle_save(request, pk):
    v = get_object_or_404(Venue, pk=pk)
    obj, created = SavedVenue.objects.get_or_create(user=request.user, venue=v)
    if not created:
        obj.delete()
    return Response({"is_saved": created})


@api_view(["GET"])
@permission_classes([permissions.IsAuthenticated])
def saved(request):
    lat, lng = _coords(request)
    qs = [sv.venue for sv in request.user.saved_venues.select_related("venue__area__city")
          .prefetch_related("venue__venue_sports__sport", "venue__photos")]
    ids = {v.id for v in qs}
    return Response([venue_card(request, v, lat, lng, ids) for v in qs])


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def review(request, pk):
    from bookings.models import Booking
    v = get_object_or_404(Venue, pk=pk)
    rating = int(request.data.get("rating", 0))
    if not 1 <= rating <= 5:
        raise ValidationError({"rating": "Rating must be between 1 and 5."})
    booking = Booking.objects.filter(pk=request.data.get("booking"), user=request.user, venue=v).first()
    if not booking or booking.status != "completed":
        raise ValidationError({"booking": "You can rate a venue after playing there."})
    Review.objects.update_or_create(booking=booking, defaults={
        "user": request.user, "venue": v, "rating": rating, "comment": request.data.get("comment", "")})
    v.refresh_from_db()
    return Response({"rating": float(v.rating), "review_count": v.review_count})
