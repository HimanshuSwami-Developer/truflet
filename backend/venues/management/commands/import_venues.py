"""Import venues from a tab-separated file (see venues/data/gurugram_venues.tsv).

    python manage.py import_venues venues/data/gurugram_venues.tsv --city Gurgaon

Columns: name, area, address, min_price, max_price, phone, email, operator, notes, sports, closes_at, lat, lng

- Missing areas are created in --city (centred on their first venue).
- Venues are matched by name + city, so re-running updates instead of duplicating.
- New venues are hidden (is_active=False, partner status "Not contacted") until onboarded.
  Existing venues keep their Active flag and partner status.
- Pricing: min_price = off-peak ₹/hr, max_price - min_price = peak surcharge, for every listed sport.
- Each new venue gets one court ("Turf 1") for all its sports so slots can be booked once it goes live.
"""
import csv
import re

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from venues.models import Area, City, Court, Sport, Venue, VenueSport

SPORT_DEFAULTS = {
    # name: (fg, bg, seed image, match minutes, team size, scoring, max players)
    "Cricket": ("#15803D", "#DCFCE7", "cricket", 60, 8, "cricket", 16),
    "Football": ("#1D4ED8", "#DBEAFE", "ball", 50, 7, "points", 14),
    "Pickleball": ("#854D0E", "#FEF3C7", "pickleball", 30, 2, "points", 4),
}
SPORT_META = {"Cricket": "Box cricket", "Football": "5/7-a-side", "Pickleball": "Doubles court"}


def first_phone(raw):
    """'+91 93100 96119 / +91 87500 07507' → '+91 93100 96119'; non-numbers → ''."""
    m = re.search(r"\+?\d[\d ]{8,}\d", raw or "")
    return m.group(0).strip()[:20] if m else ""


class Command(BaseCommand):
    help = "Import / update venues from a TSV file (hidden until onboarded)."

    def add_arguments(self, parser):
        parser.add_argument("path")
        parser.add_argument("--city", default="Gurgaon")

    def sport(self, name):
        s = Sport.objects.filter(name__iexact=name).first()
        if s:
            return s
        fg, bg, image, mins, size, scoring, _ = SPORT_DEFAULTS[name]
        s = Sport(name=name, fg_color=fg, bg_color=bg, match_minutes=mins, team_size=size, scoring=scoring,
                  order=Sport.objects.count())
        try:  # reuse the bundled demo artwork when available
            from core.management.commands.seed_demo import img
            img(s.image, image)
        except Exception:
            pass
        s.save()
        self.stdout.write(f"  + sport {name}")
        return s

    @transaction.atomic
    def handle(self, path, city, **opts):
        city_obj = City.objects.filter(name=city).first()
        if not city_obj:
            raise CommandError(f"City {city!r} not found")
        try:
            rows = list(csv.DictReader(open(path, encoding="utf-8"), delimiter="\t"))
        except FileNotFoundError:
            raise CommandError(f"{path} not found")

        created = updated = 0
        for r in rows:
            lat = float(r["lat"]) if r.get("lat") else None
            lng = float(r["lng"]) if r.get("lng") else None
            area, new_area = Area.objects.get_or_create(
                city=city_obj, name=r["area"].strip(),
                defaults={"lat": lat, "lng": lng, "order": city_obj.areas.count()})
            if new_area:
                self.stdout.write(f"  + area {area.name}")

            phone_raw = r["phone"].strip()
            email = r["email"].strip()
            notes = [r["notes"].strip()]
            if first_phone(phone_raw):
                extra = [p.strip() for p in phone_raw.split("/")[1:] if first_phone(p)]
                if extra:
                    notes.append("Other phones: " + ", ".join(extra))
            elif phone_raw:
                notes.append(f"Phone: {phone_raw}")  # e.g. Walk-in / Google Business
            if "@" not in email:
                notes.append(f"Email: {email}")
                email = ""

            v = Venue.objects.filter(name=r["name"].strip(), area__city=city_obj).first()
            is_new = v is None
            if is_new:
                v = Venue(name=r["name"].strip(), is_active=False, partner_status="not_contacted",
                          surface="Artificial turf", size="")
            v.area = area
            v.address = r["address"].strip()
            v.lat, v.lng = lat, lng
            v.phone = first_phone(r["phone"])
            v.contact_email = email
            v.operator_type = r["operator"].strip()
            v.internal_notes = "\n".join(n for n in notes if n)
            v.closes_at = int(r.get("closes_at") or 24)
            v.save()

            low, high = int(r["min_price"]), int(r["max_price"])
            sports = [self.sport(n.strip()) for n in r["sports"].split(",") if n.strip()]
            for s in sports:
                VenueSport.objects.update_or_create(
                    venue=v, sport=s,
                    defaults={"base_price": low, "peak_surcharge": max(0, high - low), "meta": SPORT_META.get(s.name, ""),
                              "max_players": SPORT_DEFAULTS.get(s.name, (0,) * 7)[6] or 16})
            if not v.courts.exists():
                court = Court.objects.create(venue=v, name="Turf 1", meta=" / ".join(s.name for s in sports))
                court.sports.set(sports)
            created += is_new
            updated += not is_new

        self.stdout.write(self.style.SUCCESS(f"{created} venues added, {updated} updated (new ones are hidden)."))
