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
            "image": image_url(request, s.image), "match_minutes": s.match_minutes, "team_size": s.team_size,
            "scoring": s.scoring}


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


def venue_card(request, v, lat=None, lng=None, saved_ids=frozenset()):
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


@api_view(["GET"])
def venue_list(request):
    qs = (Venue.objects.filter(is_active=True)
          .select_related("area__city").prefetch_related("venue_sports__sport", "photos"))
    p = request.GET
    if p.get("city"):
        qs = qs.filter(area__city_id=p["city"])
    elif p.get("area"):
        area = Area.objects.filter(pk=p["area"]).first()
        if area:
            qs = qs.filter(area__city_id=area.city_id)
    if p.get("sport"):
        qs = qs.filter(venue_sports__sport_id=p["sport"])
    if p.get("q"):
        q = p["q"]
        qs = qs.filter(Q(name__icontains=q) | Q(area__name__icontains=q) | Q(venue_sports__sport__name__icontains=q))
    if p.get("saved") and request.user.is_authenticated:
        qs = qs.filter(saved_by__user=request.user)
    qs = qs.distinct()
    lat, lng = _coords(request)
    saved = _saved_ids(request)
    items = [venue_card(request, v, lat, lng, saved) for v in qs]
    sort = p.get("sort", "near")
    if sort == "price":
        items.sort(key=lambda x: x["price_from"])
    elif sort == "rating":
        items.sort(key=lambda x: -x["rating"])
    else:
        items.sort(key=lambda x: (x["distance_km"] is None, x["distance_km"] or 0))
    return Response(items)


@api_view(["GET"])
def venue_detail(request, pk):
    v = get_object_or_404(Venue.objects.select_related("area__city")
                          .prefetch_related("venue_sports__sport", "photos", "amenities", "courts__sports"),
                          pk=pk, is_active=True)
    lat, lng = _coords(request)
    data = venue_card(request, v, lat, lng, _saved_ids(request))
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
    return Response({"date": day.isoformat(), "court": court.id, "sport": vs.sport_id,
                     "slots": slot_grid(vs, court, day)})


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
