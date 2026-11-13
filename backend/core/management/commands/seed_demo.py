"""Load the sample data used in the Turflet design.

    python manage.py seed_demo            # adds data (idempotent-ish, skips if venues exist)
    python manage.py seed_demo --reset    # wipes app data first

Images in seed_images/ are uploaded through the default storage, so with CLOUDINARY_URL
set they land in Cloudinary.
"""
from datetime import date, timedelta
from pathlib import Path

from django.conf import settings
from django.core.files import File
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from accounts.models import PlayerSport, User
from bookings.models import Booking, Coupon
from core.models import FAQ, AppConfig, PolicySection, RefundRule
from venues.models import Amenity, Area, City, Court, Sport, Venue, VenuePhoto, VenueSport

IMG_DIR = Path(settings.BASE_DIR) / "seed_images"
_cache = {}


def img(field, name):
    """Save seed image `name` into an ImageField (re-using the stored name after the first upload)."""
    if name in _cache:
        field.name = _cache[name]
        return
    with open(IMG_DIR / f"{name}.jpg", "rb") as fh:
        field.save(f"{name}.jpg", File(fh), save=False)
    _cache[name] = field.name


class Command(BaseCommand):
    help = "Seed demo data matching the app design"

    def add_arguments(self, parser):
        parser.add_argument("--reset", action="store_true")

    @transaction.atomic
    def handle(self, *args, **opts):
        if opts["reset"]:
            from community.models import Lobby
            Lobby.objects.all().delete()
            for m in (Booking,
                      Coupon, VenuePhoto, VenueSport, Court, Venue, Amenity, PlayerSport, Sport,
                      FAQ, PolicySection, RefundRule):
                m.objects.all().delete()
            User.objects.filter(is_staff=False).delete()
        if Venue.objects.exists():
            self.stdout.write(self.style.WARNING("Venues exist already — use --reset to reseed."))
            return
        self.config()
        self.locations()
        self.catalog()
        self.venues()
        self.content()
        self.people()
        self.matches()
        self.owner()
        self.stdout.write(self.style.SUCCESS("Demo data loaded. Demo player: arjun@turflet.app, demo turf owner: "
                                             "owner@turflet.app (code 123456 in dev mode)."))

    def matches(self):
        """Open lobbies so the solo flow, screening and Match Room have something to show."""
        from bookings import services as booking_services
        from community import services as match
        S = {s.name: s for s in Sport.objects.all()}
        U = {u.name: u for u in User.objects.all()}
        me = U["Arjun Mehta"]
        tomorrow = timezone.localdate() + timedelta(days=1)
        kick = Venue.objects.get(name="Kickoff Football Hub")
        gf = Venue.objects.get(name="Greenfield Sports Arena")

        def friends(*names):
            return [{"user_id": U[n].id, "tag": "known"} for n in names]

        # 1 · crowdfunding: the turf isn't booked until the pool covers it
        lobby, _ = match.create_lobby(U["Arif Khan"], {
            "venue": kick.id, "court": kick.courts.get(name="Pitch 1").id, "sport": S["Football"].id,
            "date": tomorrow.isoformat(), "start_hour": 19, "duration": 1, "capacity": 10,
            "payment_rule": "split", "booking_mode": "crowdfund", "is_public": True,
            "friends": friends("Faiz Ahmed", "Imran Shaikh", "Varun Nair") + [{"tag": "guest", "name": "Sameer"}]})
        for n in ("Arif Khan", "Faiz Ahmed", "Imran Shaikh"):
            match.pay_share(lobby, U[n], "upi")
        match.send(lobby, U["Arif Khan"], "Bring a white and a dark tee 👕")

        # 2 · book & recover: the host paid upfront, solo shares are recovered through escrow
        lobby, booking = match.create_lobby(U["Vikram Joshi"], {
            "venue": gf.id, "court": gf.courts.get(name="Court B").id, "sport": S["Cricket"].id,
            "date": tomorrow.isoformat(), "start_hour": 20, "duration": 2, "capacity": 12,
            "payment_rule": "split", "booking_mode": "book_recover", "is_public": True,
            "friends": friends("Kabir Rao", "Rohan Kulkarni", "Siddharth Pai", "Dev Shetty", "Karan Gill")})
        booking_services.pay(booking, "upi")
        lobby.refresh_from_db()
        for n in ("Kabir Rao", "Rohan Kulkarni", "Siddharth Pai"):
            match.pay_share(lobby, U[n], "upi")

        # 3 · the demo player hosts one, with a solo request waiting for screening
        lobby, _ = match.create_lobby(me, {
            "venue": gf.id, "court": gf.courts.get(name="Court C").id, "sport": S["Cricket"].id,
            "date": (tomorrow + timedelta(days=1)).isoformat(), "start_hour": 19, "duration": 2, "capacity": 10,
            "payment_rule": "split", "booking_mode": "crowdfund", "is_public": True,
            "friends": friends("Aditya Mehra", "Karan Gill")})
        match.pay_share(lobby, me, "upi")
        match.request_join(lobby, U["Meera Iyer"], "Hi! I play cricket most weekends — happy to bowl. Can I join?")

    def owner(self):
        """A turf owner who manages the first venue, to try the owner view of the admin panel."""
        u = User.objects.create_user("owner@turflet.app", name="Ravi Turf Owner", phone="+919800000999",
                                     is_venue_owner=True)
        Venue.objects.filter(pk=Venue.objects.order_by("pk").values_list("pk", flat=True).first()).update(owner=u)

    # ------------------------------------------------------------------
    def config(self):
        c = AppConfig.get()
        c.policy_updated_on = date(2026, 11, 1)
        img(c.offer_image, "stumps")
        c.save()
        Coupon.objects.create(code="PLAY100", description="₹100 off your first booking", value=100,
                              first_booking_only=True, per_user_limit=1)

    def locations(self):
        data = {
            "Bengaluru": [("Koramangala", 12.9352, 77.6245), ("HSR Layout", 12.9116, 77.6474),
                          ("Indiranagar", 12.9784, 77.6408), ("Whitefield", 12.9698, 77.7500),
                          ("BTM Layout", 12.9166, 77.6101), ("Domlur", 12.9609, 77.6387), ("Ejipura", 12.9406, 77.6278)],
            "Mumbai": [("Andheri West", 19.1364, 72.8296), ("Powai", 19.1176, 72.9060), ("Bandra", 19.0596, 72.8295),
                       ("Thane", 19.2183, 72.9781)],
            "Pune": [("Baner", 18.5590, 73.7868), ("Kothrud", 18.5074, 73.8077), ("Viman Nagar", 18.5679, 73.9143),
                     ("Hinjewadi", 18.5913, 73.7389)],
            "Hyderabad": [("Gachibowli", 17.4401, 78.3489), ("Madhapur", 17.4483, 78.3915),
                          ("Kondapur", 17.4622, 78.3568), ("Banjara Hills", 17.4156, 78.4347)],
            "Jaipur": [("Malviya Nagar", 26.8549, 75.8243), ("Vaishali Nagar", 26.9124, 75.7270),
                       ("C-Scheme", 26.9050, 75.7998), ("Mansarovar", 26.8505, 75.7628)],
        }
        for ci, (city, areas) in enumerate(data.items()):
            c, _ = City.objects.get_or_create(name=city, defaults={"order": ci, "is_live": True})
            for ai, (name, lat, lng) in enumerate(areas):
                Area.objects.get_or_create(city=c, name=name, defaults={"lat": lat, "lng": lng, "order": ai})

    def catalog(self):
        sports = [
            ("Cricket", "#15803D", "#DCFCE7", "cricket"),
            ("Football", "#1D4ED8", "#DBEAFE", "ball"),
            ("Badminton", "#6D28D9", "#EDE9FE", "racket"),
            ("Pickleball", "#854D0E", "#FEF3C7", "pickleball"),
            ("Tennis", "#0E7490", "#CFFAFE", "tennis"),
            ("Basketball", "#C2410C", "#FFEDD5", "basketball"),
        ]
        for i, (name, fg, bg, image) in enumerate(sports):
            s = Sport(name=name, fg_color=fg, bg_color=bg, order=i)
            img(s.image, image)
            s.save()
        amen = [("Parking", "parking", "#1D4ED8", "#DBEAFE"), ("Floodlights", "floodlights", "#854D0E", "#FEF3C7"),
                ("Washroom", "washroom", "#6D28D9", "#EDE9FE"), ("Water", "water", "#0E7490", "#CFFAFE"),
                ("Changing room", "changing", "#C2410C", "#FFEDD5"), ("Equipment", "equipment", "#15803D", "#DCFCE7"),
                ("Covered roof", "covered", "#0F766E", "#CCFBF1")]
        for i, (n, icon, fg, bg) in enumerate(amen):
            Amenity.objects.create(name=n, icon=icon, fg_color=fg, bg_color=bg, order=i)

    def venues(self):
        S = {s.name: s for s in Sport.objects.all()}
        A = {a.name: a for a in Area.objects.filter(city__name="Bengaluru")}
        amenities = list(Amenity.objects.all())
        rows = [
            dict(name="Greenfield Sports Arena", area="HSR Layout", lat=12.9121, lng=77.6446, rating=4.7, reviews=1200,
                 fast=True, hl="Floodlit", cover="cricket", photos=["turf", "stumps", "football"],
                 address="27th Main Rd, Sector 2, HSR Layout, Bengaluru 560102",
                 sports=[("Cricket", "Box · 8-a-side", 1200, "stumps"), ("Football", "5 / 7-a-side", 1400, "ball")],
                 courts=[("Court A", "Box · 8-a-side"), ("Court B", "Box · 6-a-side"), ("Court C", "Open · 8-a-side")]),
            dict(name="Pitch Perfect Box Cricket", area="Koramangala", lat=12.9340, lng=77.6200, rating=4.5, reviews=860,
                 fast=False, hl="Covered", cover="turf", photos=["cricket"], address="80 Feet Rd, 4th Block, Koramangala",
                 sports=[("Cricket", "Box · 6-a-side", 900, None)], courts=[("Court A", "Box · 6-a-side"), ("Court B", "Box · 6-a-side")]),
            dict(name="Kickoff Football Hub", area="BTM Layout", lat=12.9150, lng=77.6050, rating=4.6, reviews=640,
                 fast=True, hl="7-a-side", cover="football", photos=["ball"], address="16th Main, BTM 2nd Stage",
                 sports=[("Football", "5 / 7-a-side", 1500, None)], courts=[("Pitch 1", "7-a-side"), ("Pitch 2", "5-a-side")]),
            dict(name="Smash Court Badminton", area="Indiranagar", lat=12.9790, lng=77.6400, rating=4.4, reviews=410,
                 fast=False, hl="Wooden floor", cover="badminton_court", photos=["racket"], address="100 Feet Rd, Indiranagar",
                 sports=[("Badminton", "Synthetic · singles/doubles", 500, None)],
                 courts=[("Court 1", "Wooden"), ("Court 2", "Wooden"), ("Court 3", "Wooden"), ("Court 4", "Synthetic")]),
            dict(name="Rally Pickleball Club", area="Domlur", lat=12.9610, lng=77.6380, rating=4.8, reviews=290,
                 fast=False, hl="Outdoor", cover="tennis", photos=["pickleball"], address="Domlur Layout, Bengaluru",
                 sports=[("Pickleball", "Doubles", 700, None), ("Tennis", "Hard court", 900, None)],
                 courts=[("Court 1", "Outdoor"), ("Court 2", "Outdoor")]),
            dict(name="Hoops Arena", area="Ejipura", lat=12.9400, lng=77.6290, rating=4.3, reviews=180,
                 fast=False, hl="Full court", cover="basketball", photos=[], address="Ejipura Main Rd, Bengaluru",
                 sports=[("Basketball", "Full court · 5v5", 800, None)], courts=[("Full court", "Indoor")]),
        ]
        for r in rows:
            v = Venue(name=r["name"], area=A[r["area"]], lat=r["lat"], lng=r["lng"], address=r["address"],
                      rating=r["rating"], review_count=r["reviews"], is_fast_filling=r["fast"], highlight=r["hl"],
                      phone="+918000000001", surface="Artificial grass", size="100 × 60 ft",
                      about="Covered box turf with FIFA-grade artificial grass, LED floodlights for night games and nets "
                            "around every court. Bats, stumps and footballs available at the counter.",
                      rules="Non-marking shoes or studs only\nArrive 10 minutes before your slot\n"
                            "Free cancellation up to 6 hours before")
            img(v.cover, r["cover"])
            v.save()
            v.amenities.set(amenities)
            for i, p in enumerate(r["photos"]):
                ph = VenuePhoto(venue=v, order=i)
                img(ph.image, p)
                ph.save()
            sport_objs = []
            for name, meta, price, image in r["sports"]:
                vs = VenueSport(venue=v, sport=S[name], meta=meta, base_price=price, peak_surcharge=300)
                if image:
                    img(vs.image, image)
                vs.save()
                sport_objs.append(S[name])
            for i, (cname, meta) in enumerate(r["courts"]):
                c = Court.objects.create(venue=v, name=cname, meta=meta, order=i)
                c.sports.set(sport_objs)

    def content(self):
        faqs = [
            ("How do I cancel or reschedule a booking?", "Open Bookings, pick the booking and tap Cancel or Reschedule. Rescheduling is free once, up to 2 hours before your slot."),
            ("When will I get my refund?", "Eligible refunds go back to your original payment method within 5–7 working days. UPI refunds usually arrive within 48 hours."),
            ("Do I need an account to book?", "No password needed. Sign in with a one-time code sent to your email. Your QR ticket holds every booking detail the venue needs."),
            ("What if it rains or the venue closes?", "If the venue cancels or the slot cannot be played due to weather, you get a 100% refund including the convenience fee."),
            ("Can I add more players or extend my slot?", "Extensions depend on the next slot being free. Ask at the counter or chat with us — we will update your ticket."),
        ]
        for i, (q, a) in enumerate(faqs):
            FAQ.objects.create(question=q, answer=a, order=i)
        RefundRule.objects.create(min_hours_before=24, percent=100, title="24 hrs or more before", subtitle="Full refund of slot charges")
        RefundRule.objects.create(min_hours_before=6, percent=50, title="6 – 24 hrs before", subtitle="Half of slot charges refunded")
        RefundRule.objects.create(min_hours_before=0, percent=0, title="Under 6 hrs / no-show", subtitle="Not refundable — reschedule instead")
        notes = [
            ("Refund timeline", "5–7 working days to your original payment method. UPI is usually within 48 hours.", "clock", "blue"),
            ("Free reschedule", "once per booking, up to 2 hours before the slot, subject to availability.", "refresh", "purple"),
            ("Rain-out or venue cancels", "100% refund including the convenience fee.", "cloud", "teal"),
            ("Convenience fee", "is non-refundable for cancellations you make.", "receipt", "gray"),
        ]
        for i, (h, b, icon, color) in enumerate(notes):
            PolicySection.objects.create(kind="refund_note", heading=h, body=b, icon=icon, color=color, order=i)
        privacy = [
            ("What we collect", ["Email address (for sign-in codes and booking confirmations)", "Mobile number, only if you add one for the venue to contact you", "Name you enter for the booking", "Approximate location, only when you allow it", "Booking and payment status — card or UPI details stay with the payment gateway"]),
            ("How we use it", ["Confirm, change or cancel your bookings", "Generate the QR ticket the venue scans", "Send reminders and slot alerts you opt into"]),
            ("Who we share it with", ["The venue you booked — name, contact and slot only", "Our payment partner to process payments and refunds", "We never sell your data to advertisers"]),
            ("Your choices", ["Turn off location and alerts anytime in phone settings", "Ask us to delete your booking history via support", "Booking records are kept for 3 years for tax purposes"]),
        ]
        for i, (h, items) in enumerate(privacy):
            PolicySection.objects.create(kind="privacy", heading=h, body="\n".join(items), order=i)
        PolicySection.objects.create(kind="terms", heading="Rules for players & venues",
                                     body="Respect venue rules and timings\nNo-shows are not refunded\nVenues must honour confirmed bookings")

    def people(self):
        S = {s.name: s for s in Sport.objects.all()}
        kor = Area.objects.get(name="Koramangala")
        me = User.objects.create_user("arjun@turflet.app", phone="+919800000521", name="Arjun Mehta",
                                      address="4th Block, Koramangala, Bengaluru 560034", handle="arjun.plays", home_area=kor,
                                      lat=12.9352, lng=77.6245)
        PlayerSport.objects.create(user=me, sport=S["Cricket"], level=2)
        PlayerSport.objects.create(user=me, sport=S["Badminton"], level=1)
        PlayerSport.objects.create(user=me, sport=S["Football"], level=0)
        names = ["Rohan Kulkarni", "Aditya Mehra", "Siddharth Pai", "Karan Gill", "Ananya Menon", "Neha Verma",
                 "Dev Shetty", "Kabir Rao", "Meera Iyer", "Vikram Joshi", "Sara Thomas", "Arif Khan", "Imran Shaikh",
                 "Leela Prasad", "Varun Nair", "Ajay Mohan", "Faiz Ahmed", "Tanvi Rao"]
        people = {}
        for i, n in enumerate(names):
            u = User.objects.create_user(f"{n.split()[0].lower()}.{n.split()[1].lower()}@example.com", name=n, home_area=kor, lat=12.93 + i * 0.002, lng=77.62 + i * 0.002)
            people[n] = u
        for n, sport, lvl in [("Vikram Joshi", "Cricket", 2), ("Sara Thomas", "Pickleball", 0), ("Arif Khan", "Football", 1),
                              ("Kabir Rao", "Cricket", 1), ("Meera Iyer", "Badminton", 1)]:
            PlayerSport.objects.create(user=people[n], sport=S[sport], level=lvl)
        for n in ["Rohan Kulkarni", "Siddharth Pai"]:
            PlayerSport.objects.get_or_create(user=people[n], sport=S["Cricket"], defaults={"level": 1})

        gf = Venue.objects.get(name="Greenfield Sports Arena")
        smash = Venue.objects.get(name="Smash Court Badminton")
        kick = Venue.objects.get(name="Kickoff Football Hub")
        today = timezone.localdate()
        now = timezone.now()

        def book(user, venue, sport, court, d, h, dur, status="confirmed", total=None):
            vs = VenueSport.objects.get(venue=venue, sport=S[sport])
            slot = sum(vs.price_for(x) for x in range(h, h + dur))
            b = Booking.objects.create(
                user=user, venue=venue, sport=S[sport], court=venue.courts.get(name=court), date=d, start_hour=h,
                duration=dur, slot_amount=slot, convenience_fee=40, gst=7, total=total or slot + 47, status=status,
                payment_status="paid", payment_method="upi", transaction_id="UPI/6311/0749/2201",
                paid_at=now - timedelta(hours=1), peak_hours=sum(1 for x in range(h, h + dur) if venue.is_peak(x)))
            return b

        # upcoming bookings for the demo player (shown in "My bookings")
        book(me, gf, "Cricket", "Court A", today + timedelta(days=1), 18, 2)
        book(me, smash, "Badminton", "Court 2", today + timedelta(days=3), 7, 1)
        book(me, kick, "Football", "Pitch 1", today - timedelta(days=6), 20, 2, status="completed")
        book(me, Venue.objects.get(name="Pitch Perfect Box Cricket"), "Cricket", "Court B", today - timedelta(days=13), 7, 2, status="completed")
        hoops = book(me, Venue.objects.get(name="Hoops Arena"), "Basketball", "Full court", today - timedelta(days=10), 18, 1)
        hoops.status, hoops.payment_status, hoops.refund_amount = "cancelled", "refunded", hoops.total
        hoops.cancelled_at = hoops.refunded_at = now - timedelta(days=12)
        hoops.save()
        # someone else's bookings so the slot grid shows "Booked"
        for h in (7, 12, 16, 21):
            book(people["Karan Gill"], gf, "Cricket", "Court A", today + timedelta(days=1), h, 1)
