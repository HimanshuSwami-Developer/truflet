from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from . import service as payments

User = get_user_model()


class WalletTests(TestCase):
    def setUp(self):
        self.u = User.objects.create_user("w@x.com", name="Wally", phone="+919800000021", wallet_balance=500)

    def balance(self):
        return payments.wallet_balance(self.u.pk)

    def test_wallet_charge_debits_and_refuses_when_short(self):
        r = payments.charge(self.u.pk, 300, "wallet", reference="T1")
        self.assertTrue(r.success)
        self.assertTrue(r.transaction_id.startswith("WALLET/"))
        self.assertEqual(self.balance(), 200)
        r = payments.charge(self.u.pk, 300, "wallet", reference="T2")
        self.assertEqual((r.success, r.message), (False, "Not enough Turflet balance."))
        self.assertEqual(self.balance(), 200)

    def test_gateway_charge_leaves_wallet_alone_and_checks_upi(self):
        self.assertTrue(payments.charge(self.u.pk, 300, "upi", reference="T1", upi_id="me@bank").success)
        self.assertFalse(payments.charge(self.u.pk, 300, "upi", reference="T2", upi_id="nope").success)
        self.assertEqual(self.balance(), 500)

    def test_refund_goes_back_the_way_it_was_paid(self):
        payments.refund(self.u.pk, 100, "wallet", "WALLET/1")
        self.assertEqual(self.balance(), 600)
        payments.refund(self.u.pk, 100, "upi", "UPI/1")
        self.assertEqual(self.balance(), 600)

    def test_debit_is_all_or_nothing_and_adjust_never_goes_negative(self):
        self.assertFalse(payments.debit_wallet(self.u.pk, 501))
        self.assertTrue(payments.debit_wallet(self.u.pk, 500))
        self.assertEqual(payments.adjust_wallet(self.u.pk, -50), 0)
        self.assertEqual(payments.adjust_wallet(self.u.pk, 75), 75)


class BookingWalletRefundTests(TestCase):
    """A booking paid from the wallet and cancelled by the venue is refunded to the wallet."""

    def test_venue_cancellation_refunds_wallet(self):
        from bookings import services as bookings
        from core.models import AppConfig
        from venues.models import Area, City, Court, Sport, Venue, VenueSport

        AppConfig.objects.create(pk=1, convenience_fee=40)
        area = Area.objects.create(city=City.objects.create(name="B", is_live=True), name="HSR", lat=1, lng=1)
        sport = Sport.objects.create(name="Football")
        venue = Venue.objects.create(name="Arena", area=area, address="x", lat=1, lng=1, opens_at=6, closes_at=24,
                                     peak_start=30, peak_end=30)
        VenueSport.objects.create(venue=venue, sport=sport, base_price=1000, max_players=14)
        court = Court.objects.create(venue=venue, name="Pitch 1")
        court.sports.add(sport)
        u = User.objects.create_user("p@x.com", name="Pat", phone="+919800000022", wallet_balance=5000)

        b = bookings.create_hold(u, venue, court.id, sport.id, timezone.localdate() + timedelta(days=2), 10, 1)
        b = bookings.pay(b, "wallet")
        self.assertEqual(payments.wallet_balance(u.pk), 5000 - b.total)
        bookings.cancel(b, "Rain", by_venue=True)
        self.assertEqual(payments.wallet_balance(u.pk), 5000)
