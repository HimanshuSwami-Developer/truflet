"""Match flows end to end through the API.

    DATABASE_URL=sqlite:///tmp.sqlite3 python manage.py test community
"""
from datetime import datetime, timedelta
from unittest import mock

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from bookings.models import Booking
from core.models import AppConfig
from venues.models import Amenity, Area, City, Court, Sport, Venue, VenueSport

from .models import Lobby, LobbyMember


class MatchTestCase(TestCase):
    def setUp(self):
        AppConfig.objects.create(pk=1, split_fee=10, convenience_fee=40)
        city = City.objects.create(name="Bengaluru", is_live=True)
        self.area = Area.objects.create(city=city, name="HSR", lat=12.9121, lng=77.6446)
        self.sport = Sport.objects.create(name="Football")
        self.venue = Venue.objects.create(name="Arena", area=self.area, address="x", lat=12.9121, lng=77.6446,
                                          opens_at=6, closes_at=24, peak_start=30, peak_end=30)
        VenueSport.objects.create(venue=self.venue, sport=self.sport, base_price=1000, max_players=14)
        self.court = Court.objects.create(venue=self.venue, name="Pitch 1")
        self.court.sports.add(self.sport)
        self.host = User.objects.create_user("host@x.com", name="Hana Host", phone="+919800000001")
        self.friend = User.objects.create_user("friend@x.com", name="Fred Friend", phone="+919800000002")
        self.solo = User.objects.create_user("solo@x.com", name="Sam Solo", phone="+919800000003")
        self.other = User.objects.create_user("other@x.com", name="Oli Other", phone="+919800000004")
        self.day = timezone.localdate() + timedelta(days=2)

    def api(self, user):
        c = APIClient()
        c.force_authenticate(user)
        return c

    def create(self, **extra):
        body = {"venue": self.venue.id, "court": self.court.id, "sport": self.sport.id, "date": self.day.isoformat(),
                "start_hour": 19, "duration": 1, "capacity": 4, "payment_rule": "split",
                "booking_mode": "crowdfund", "is_public": True,
                "friends": [{"contact": "friend@x.com", "tag": "known"}, {"tag": "guest", "name": "Gus"}]}
        body.update(extra)
        r = self.api(self.host).post("/api/v1/lobbies/", body, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        return r.data

    def screen_in(self, lobby_id, user):
        r = self.api(user).post(f"/api/v1/lobbies/{lobby_id}/request/", {"message": "Can I play?"}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        rid = r.data["id"]
        r = self.api(self.host).post(f"/api/v1/lobbies/{lobby_id}/requests/{rid}/approve/")
        self.assertEqual(r.status_code, 200, r.data)
        return rid

    def pay(self, lobby_id, user):
        r = self.api(user).post(f"/api/v1/lobbies/{lobby_id}/pay/", {"method": "upi"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        return r.data


class CrowdfundTests(MatchTestCase):
    def test_crowdfund_locks_turf_when_pool_is_full(self):
        lb = self.create()
        self.assertEqual(lb["status"], "crowdfunding")
        self.assertEqual(lb["share"], 250)  # ₹1000 / 4
        # crowdfunding never blocks the turf calendar
        slots = self.client.get(f"/api/v1/venues/{self.venue.id}/availability/",
                                {"date": self.day, "sport": self.sport.id, "court": self.court.id}).data["slots"]
        s19 = next(s for s in slots if s["hour"] == 19)
        self.assertEqual(s19["status"], "free")
        self.assertEqual((s19["lobbies"], s19["lobby_spots"]), (1, 1))

        checkout = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/pay/").data
        self.assertEqual((checkout["guest_shares"], checkout["total"]), (250, 510))  # own + guest share + fee
        self.pay(lb["id"], self.host)
        self.pay(lb["id"], self.friend)
        self.screen_in(lb["id"], self.solo)
        data = self.pay(lb["id"], self.solo)
        self.assertEqual(data["status"], "locked")
        self.assertEqual(data["payout"]["status"], "settled")  # pool paid to the venue, not the host
        b = Booking.objects.get(pk=data["booking"]["id"])
        self.assertEqual((b.status, b.payment_method, b.total), ("confirmed", "pool", 1000))
        self.assertEqual(User.objects.get(pk=self.host.pk).wallet_balance, 0)

    def test_slot_taken_alert_then_switch(self):
        lb = self.create()
        # another group books the exact slot first
        Booking.objects.create(user=self.other, venue=self.venue, court=self.court, sport=self.sport, date=self.day,
                               start_hour=19, status="confirmed", total=1000)
        data = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/").data
        self.assertEqual(data["alert"], "slot_taken")
        r = self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/switch-slot/",
                                     {"date": self.day.isoformat(), "start_hour": 21}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual((r.data["start_hour"], r.data["alert"]), (21, ""))

    def test_unfilled_alert_and_pay_balance(self):
        lb = self.create()
        self.pay(lb["id"], self.host)
        kickoff = Lobby.objects.get(pk=lb["id"]).start_dt
        with mock.patch.object(timezone, "now", return_value=kickoff - timedelta(minutes=45)):
            data = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/").data
            self.assertEqual(data["alert"], "unfilled")
            self.assertEqual(data["host_actions"]["pay_balance"], 500)
            r = self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/pay-balance/", {"method": "upi"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["status"], "locked")
        # the friend still owes a share → it now recovers the host's balance through escrow
        self.pay(lb["id"], self.friend)
        self.assertEqual(Lobby.objects.get(pk=lb["id"]).payout_status, "held")

    def test_expires_and_refunds_if_not_funded_by_kickoff(self):
        lb = self.create()
        self.pay(lb["id"], self.host)
        kickoff = Lobby.objects.get(pk=lb["id"]).start_dt
        with mock.patch.object(timezone, "now", return_value=kickoff + timedelta(minutes=1)):
            data = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/").data
        self.assertEqual(data["status"], "expired")
        self.assertEqual(LobbyMember.objects.get(lobby_id=lb["id"], tag="host").escrow, "refunded")


class ScreeningTests(MatchTestCase):
    def test_requester_never_sees_main_chat_until_approved(self):
        lb = self.create()
        self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/messages/", {"body": "Squad only: gate code 4411"})
        r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/request/", {"message": "Hi"}, format="json")
        rid = r.data["id"]
        self.assertEqual(self.api(self.solo).get(f"/api/v1/lobbies/{lb['id']}/messages/").status_code, 400)
        detail = self.api(self.solo).get(f"/api/v1/lobbies/{lb['id']}/").data
        self.assertNotIn("members", detail)
        self.assertEqual(detail["my_role"], "requested")
        # 1-on-1 thread works both ways, and is private to the pair
        self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/messages/", {"body": "Can you keep?"})
        thread = self.api(self.solo).get(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/messages/").data
        self.assertIn("Can you keep?", [m["body"] for m in thread])
        self.assertEqual(self.api(self.other).get(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/messages/").status_code, 400)
        requests = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/requests/").data
        self.assertIn("score", requests[0]["player"])

        self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/approve/")
        chat = self.api(self.solo).get(f"/api/v1/lobbies/{lb['id']}/messages/").data
        self.assertIn("Squad only: gate code 4411", [m["body"] for m in chat])
        card = [m for m in chat if m["kind"] == "payment" and m["card"]["is_me"]][0]["card"]
        self.assertEqual((card["amount"], card["status"]), (260, "pending"))
        self.assertIsNotNone(card["pay_by"])

    def test_declined_closes_thread(self):
        lb = self.create()
        rid = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/request/", {}, format="json").data["id"]
        self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/decline/")
        r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/requests/{rid}/messages/", {"body": "pls"})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/request/").status_code, 400)

    def test_unpaid_spot_reopens_after_15_minutes(self):
        lb = self.create()
        self.screen_in(lb["id"], self.solo)
        self.assertEqual(self.client.get(f"/api/v1/venues/{self.venue.id}/lobbies/").data, [])  # full
        with mock.patch.object(timezone, "now", return_value=timezone.now() + timedelta(minutes=16)):
            r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/pay/", {"method": "upi"}, format="json")
            self.assertEqual(r.status_code, 400)
            self.assertEqual(len(self.client.get(f"/api/v1/venues/{self.venue.id}/lobbies/").data), 1)
        self.assertEqual(LobbyMember.objects.get(lobby_id=lb["id"], user=self.solo).status, "removed")

    def test_host_covers_all_confirms_joiners_free(self):
        lb = self.create(payment_rule="host")
        self.assertEqual(lb["status"], "draft")
        r = self.api(self.host).post(f"/api/v1/bookings/{lb['checkout_booking']['id']}/pay/", {"method": "upi"})
        self.assertEqual(r.status_code, 200, r.data)
        self.screen_in(lb["id"], self.solo)
        m = LobbyMember.objects.get(lobby_id=lb["id"], user=self.solo)
        self.assertEqual((m.status, m.amount_due), ("confirmed", 0))


class BookAndRecoverTests(MatchTestCase):
    def locked(self):
        lb = self.create(booking_mode="book_recover")
        self.assertEqual(lb["status"], "draft")
        r = self.api(self.host).post(f"/api/v1/bookings/{lb['checkout_booking']['id']}/pay/", {"method": "upi"})
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(r.data["lobby"]["status"], "locked")
        # the turf is blocked now
        slots = self.client.get(f"/api/v1/venues/{self.venue.id}/availability/",
                                {"date": self.day, "sport": self.sport.id, "court": self.court.id}).data["slots"]
        self.assertEqual(next(s for s in slots if s["hour"] == 19)["status"], "booked")
        return lb

    def test_venue_qr_checkin_releases_escrow_to_host(self):
        lb = self.locked()
        self.pay(lb["id"], self.friend)
        self.screen_in(lb["id"], self.solo)
        self.pay(lb["id"], self.solo)
        self.assertEqual(User.objects.get(pk=self.host.pk).wallet_balance, 0)  # still in escrow
        from community.services import on_venue_checkin
        on_venue_checkin(Booking.objects.get(pk=lb["checkout_booking"]["id"]))
        self.assertEqual(User.objects.get(pk=self.host.pk).wallet_balance, 500)  # 2 shares, fees kept
        self.assertEqual(Lobby.objects.get(pk=lb["id"]).payout_trigger, "qr")

    def test_gps_checkin_by_host_and_solo_releases_payout(self):
        lb = self.locked()
        self.screen_in(lb["id"], self.solo)
        self.pay(lb["id"], self.solo)
        kickoff = Lobby.objects.get(pk=lb["id"]).start_dt
        here = {"lat": 12.9122, "lng": 77.6447}
        with mock.patch.object(timezone, "now", return_value=kickoff - timedelta(minutes=5)):
            far = self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/checkin/", {"lat": 12.95, "lng": 77.6})
            self.assertEqual(far.status_code, 400)
            self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/checkin/", here)
            r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/checkin/", here)
        self.assertEqual(r.status_code, 200, r.data)
        self.assertEqual(Lobby.objects.get(pk=lb["id"]).payout_trigger, "gps")

    def test_no_show_report_blocks_auto_release(self):
        lb = self.locked()
        self.screen_in(lb["id"], self.solo)
        self.pay(lb["id"], self.solo)
        lobby = Lobby.objects.get(pk=lb["id"])
        with mock.patch.object(timezone, "now", return_value=lobby.start_dt + timedelta(minutes=10)):
            r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/report/", {"reason": "Host never came"})
        self.assertEqual(r.status_code, 200, r.data)
        with mock.patch.object(timezone, "now", return_value=lobby.end_dt + timedelta(minutes=20)):
            self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/")
        self.assertEqual(User.objects.get(pk=self.host.pk).wallet_balance, 0)
        self.assertEqual(Lobby.objects.get(pk=lb["id"]).payout_status, "disputed")

    def test_silent_auto_release_after_match_end(self):
        lb = self.locked()
        self.pay(lb["id"], self.friend)
        lobby = Lobby.objects.get(pk=lb["id"])
        with mock.patch.object(timezone, "now", return_value=lobby.end_dt + timedelta(minutes=16)):
            data = self.api(self.host).get(f"/api/v1/lobbies/{lb['id']}/").data
        self.assertEqual((data["payout"]["status"], data["payout"]["trigger"]), ("released", "auto"))
        self.assertEqual(User.objects.get(pk=self.host.pk).wallet_balance, 250)

    def test_drop_off_rules(self):
        lb = self.locked()
        self.screen_in(lb["id"], self.solo)
        self.pay(lb["id"], self.solo)
        # early drop-off: refunded only once a replacement pays
        r = self.api(self.solo).post(f"/api/v1/lobbies/{lb['id']}/leave/")
        self.assertIn("replacement", r.data["message"])
        solo = LobbyMember.objects.get(lobby_id=lb["id"], user=self.solo)
        self.assertEqual((solo.refund_due, solo.escrow), (True, "held"))
        self.screen_in(lb["id"], self.other)
        self.pay(lb["id"], self.other)
        solo.refresh_from_db()
        self.assertEqual((solo.escrow, solo.status), ("refunded", "refunded"))
        # late ghosting (< 30 min): not refundable
        lobby = Lobby.objects.get(pk=lb["id"])
        with mock.patch.object(timezone, "now", return_value=lobby.start_dt - timedelta(minutes=20)):
            r = self.api(self.other).post(f"/api/v1/lobbies/{lb['id']}/leave/")
        self.assertIn("not refundable", r.data["message"])
        self.assertEqual(LobbyMember.objects.get(lobby_id=lb["id"], user=self.other).escrow, "forfeited")

    def test_venue_cancellation_refunds_everyone_in_full(self):
        lb = self.locked()
        self.pay(lb["id"], self.friend)
        from bookings.services import cancel
        b = cancel(Booking.objects.get(pk=lb["checkout_booking"]["id"]), "Rain", by_venue=True)
        self.assertEqual(b.refund_amount, b.total)
        self.assertEqual(Lobby.objects.get(pk=lb["id"]).status, "cancelled")
        self.assertEqual(LobbyMember.objects.get(lobby_id=lb["id"], user=self.friend).escrow, "refunded")

    def test_unpublish_refunds_solo_and_keeps_squad(self):
        lb = self.locked()
        self.screen_in(lb["id"], self.solo)
        self.pay(lb["id"], self.solo)
        r = self.api(self.host).post(f"/api/v1/lobbies/{lb['id']}/unpublish/")
        self.assertEqual(r.status_code, 200, r.data)
        self.assertFalse(r.data["is_public"])
        self.assertEqual(LobbyMember.objects.get(lobby_id=lb["id"], user=self.solo).escrow, "refunded")
        self.assertEqual(self.api(self.friend).get(f"/api/v1/lobbies/{lb['id']}/messages/").status_code, 200)


class SquadBuilderValidationTests(MatchTestCase):
    def test_private_squad_fills_unnamed_spots_with_guests(self):
        r = self.api(self.host).post("/api/v1/lobbies/", {
            "venue": self.venue.id, "court": self.court.id, "sport": self.sport.id, "date": self.day.isoformat(),
            "start_hour": 19, "duration": 1, "capacity": 6, "payment_rule": "split", "booking_mode": "crowdfund",
            "is_public": False, "friends": [{"contact": "friend@x.com"}]}, format="json")
        self.assertEqual(r.status_code, 201, r.data)
        self.assertEqual(LobbyMember.objects.filter(lobby_id=r.data["id"], tag="guest").count(), 4)
        host = LobbyMember.objects.get(lobby_id=r.data["id"], tag="host")
        self.assertEqual(host.share_due, 167 * 5)  # own share + 4 guests
        self.assertEqual(r.data["spots_left"], 0)

    def test_capacity_cannot_exceed_sport_max(self):
        r = self.api(self.host).post("/api/v1/lobbies/", {
            "venue": self.venue.id, "court": self.court.id, "sport": self.sport.id, "date": self.day.isoformat(),
            "start_hour": 19, "duration": 1, "capacity": 30, "is_public": True}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_unknown_friend_suggests_guest(self):
        r = self.api(self.host).get("/api/v1/lobbies/players/", {"contact": "nobody@x.com"})
        self.assertEqual(r.status_code, 400)
        self.assertIn("guest", r.data["message"])


class DiscoveryTests(MatchTestCase):
    def test_radius_expands_until_three_venues(self):
        far = [(12.94, 77.65), (12.95, 77.66), (12.96, 77.67)]  # ~3-7 km away
        for i, (lat, lng) in enumerate(far):
            v = Venue.objects.create(name=f"Far {i}", area=self.area, address="x", lat=lat, lng=lng)
            VenueSport.objects.create(venue=v, sport=self.sport, base_price=800 + i * 400)
        r = self.client.get("/api/v1/venues/", {"area": self.area.id, "lat": 12.9121, "lng": 77.6446}).data
        self.assertEqual(r["radius_km"], 5)
        self.assertIn("Expanded search to 5 km", r["notice"])
        self.assertEqual(len(r["items"]), 3)

    def test_filters(self):
        roof = Amenity.objects.create(name="Covered roof", icon="covered")
        self.venue.amenities.add(roof)
        other = Venue.objects.create(name="Open air", area=self.area, address="x")
        VenueSport.objects.create(venue=other, sport=self.sport, base_price=2500)
        r = self.client.get("/api/v1/venues/", {"area": self.area.id, "amenities": "covered"}).data
        self.assertEqual([v["name"] for v in r["items"]], ["Arena"])
        r = self.client.get("/api/v1/venues/", {"area": self.area.id, "price_max": 1500}).data
        self.assertEqual([v["name"] for v in r["items"]], ["Arena"])
        # fully booked 6–8 PM → filtered out of that window
        for h in (18, 19):
            Booking.objects.create(user=self.other, venue=self.venue, court=self.court, sport=self.sport,
                                   date=self.day, start_hour=h, status="confirmed", total=1)
        r = self.client.get("/api/v1/venues/", {"area": self.area.id, "date": self.day.isoformat(),
                                                "from_hour": 18, "to_hour": 20}).data
        self.assertNotIn("Arena", [v["name"] for v in r["items"]])

    def test_venue_card_counts_open_lobbies(self):
        self.create()
        r = self.client.get("/api/v1/venues/", {"area": self.area.id}).data
        self.assertEqual(r["items"][0]["open_lobbies"], 1)
