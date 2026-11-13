"""Matches (lobbies): a host assembles a squad for one slot, optionally recruits solo players,
screens them in a 1-on-1 thread, and collects split payments through the platform's escrow.

Money never passes through the host. Shares sit in escrow (`LobbyMember.escrow`) until:
- Crowdfund first: the pool reaches the turf price → the turf is booked and the pool settles to the venue.
- Book & recover: the host paid the turf upfront → shares are released to the host's balance when the
  venue scans the booking QR / PIN, when the host and a solo joiner check in by GPS, or at match end + 15 min
  if nobody reported a no-show.
"""
import math
from datetime import datetime, timedelta

from django.conf import settings
from django.db import models
from django.db.models import Q, Sum
from django.utils import timezone

from core.models import TimeStamped


class Lobby(TimeStamped):
    RULES = [("split", "Split equally"), ("host", "Host covers all")]
    MODES = [("book_recover", "Book & recover"), ("crowdfund", "Crowdfund first")]
    STATUS = [
        ("draft", "Waiting for host payment"),
        ("crowdfunding", "Crowdfunding"),
        ("locked", "Turf locked"),
        ("completed", "Completed"),
        ("cancelled", "Cancelled"),
        ("expired", "Expired"),
    ]
    ALERTS = [("", "None"), ("slot_taken", "Slot booked by another group"), ("unfilled", "Not full near kickoff")]
    PAYOUT = [("none", "Nothing to pay out"), ("held", "Held in escrow"), ("released", "Released to host"),
              ("settled", "Settled to venue"), ("disputed", "No-show reported"), ("refunded", "Refunded")]

    host = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="hosted_lobbies")
    venue = models.ForeignKey("venues.Venue", on_delete=models.PROTECT, related_name="lobbies")
    court = models.ForeignKey("venues.Court", on_delete=models.PROTECT, related_name="lobbies")
    sport = models.ForeignKey("venues.Sport", on_delete=models.PROTECT, related_name="lobbies")
    date = models.DateField()
    start_hour = models.PositiveSmallIntegerField()
    duration = models.PositiveSmallIntegerField(default=1)

    capacity = models.PositiveSmallIntegerField(help_text="Total players, including the host")
    payment_rule = models.CharField(max_length=10, choices=RULES, default="split")
    booking_mode = models.CharField(max_length=14, choices=MODES, default="book_recover")
    is_public = models.BooleanField(default=False, help_text="Open spots are listed for solo players")
    turf_price = models.PositiveIntegerField(help_text="Slot rent the squad splits (₹)")

    booking = models.OneToOneField("bookings.Booking", null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="lobby")
    status = models.CharField(max_length=14, choices=STATUS, default="draft", db_index=True)
    alert = models.CharField(max_length=12, choices=ALERTS, blank=True, default="")
    cancelled_by = models.CharField(max_length=10, blank=True, help_text="host / venue / system")

    payout_status = models.CharField(max_length=10, choices=PAYOUT, default="none")
    payout_trigger = models.CharField(max_length=10, blank=True, help_text="qr / gps / auto")
    payout_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["date", "start_hour"]
        verbose_name_plural = "lobbies"
        indexes = [models.Index(fields=["venue", "date"]), models.Index(fields=["court", "date"])]

    def __str__(self):
        return f"{self.sport} at {self.venue} · {self.date} {self.start_hour}:00"

    # ---------------------------------------------------------------- time
    @property
    def end_hour(self):
        return self.start_hour + self.duration

    @property
    def start_dt(self):
        tz = timezone.get_current_timezone()
        return timezone.make_aware(datetime.combine(self.date, datetime.min.time()), tz) + timedelta(hours=self.start_hour)

    @property
    def end_dt(self):
        return self.start_dt + timedelta(hours=self.duration)

    @property
    def minutes_left(self):
        return (self.start_dt - timezone.now()).total_seconds() / 60

    # ---------------------------------------------------------------- money
    @property
    def share(self):
        """Turf share each player owes (₹, rounded up)."""
        return math.ceil(self.turf_price / max(1, self.capacity))

    @property
    def is_split(self):
        return self.payment_rule == "split"

    @property
    def is_crowdfund(self):
        return self.is_split and self.booking_mode == "crowdfund"

    def pooled(self):
        """Turf shares paid into escrow (not refunded)."""
        return self.members.filter(escrow__in=("held", "settled", "released", "forfeited")).aggregate(
            s=Sum("share_paid"))["s"] or 0

    # ---------------------------------------------------------------- headcount
    def active_members(self):
        return self.members.filter(status__in=("pending", "confirmed"))

    @property
    def taken(self):
        return self.active_members().count()

    @property
    def spots_left(self):
        return max(0, self.capacity - self.taken)

    @property
    def paid_count(self):
        return self.members.filter(status="confirmed").count()

    @property
    def is_live(self):
        return self.status in ("draft", "crowdfunding", "locked")


class LobbyMember(TimeStamped):
    TAGS = [("host", "Host"), ("known", "Known"), ("guest", "Guest"), ("solo", "Solo")]
    STATUS = [("pending", "Payment pending"), ("confirmed", "Confirmed"), ("left", "Left"),
              ("removed", "Removed"), ("refunded", "Refunded")]
    ESCROW = [("none", "Nothing paid"), ("held", "Held"), ("released", "Released to host"),
              ("settled", "Settled to venue"), ("refunded", "Refunded"), ("forfeited", "Kept (late drop-off)")]

    lobby = models.ForeignKey(Lobby, on_delete=models.CASCADE, related_name="members")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.CASCADE,
                             related_name="lobby_memberships", help_text="Empty for guests who aren't on Turflet")
    guest_name = models.CharField(max_length=60, blank=True)
    tag = models.CharField(max_length=6, choices=TAGS, default="solo")
    status = models.CharField(max_length=10, choices=STATUS, default="pending")

    share_due = models.PositiveIntegerField(default=0, help_text="Turf share this person pays (₹)")
    fee_due = models.PositiveIntegerField(default=0, help_text="Platform fee (₹)")
    share_paid = models.PositiveIntegerField(default=0)
    fee_paid = models.PositiveIntegerField(default=0)
    payment_method = models.CharField(max_length=10, blank=True)
    transaction_id = models.CharField(max_length=60, blank=True)
    pay_by = models.DateTimeField(null=True, blank=True, help_text="Spot reopens if unpaid by then")
    paid_at = models.DateTimeField(null=True, blank=True)
    escrow = models.CharField(max_length=10, choices=ESCROW, default="none")
    refund_due = models.BooleanField(default=False, help_text="Left early: refunded once replaced or released")
    checked_in_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["created_at", "id"]
        constraints = [models.UniqueConstraint(fields=["lobby", "user"], condition=Q(user__isnull=False),
                                               name="one_membership_per_player")]

    def __str__(self):
        return f"{self.display_name} · lobby {self.lobby_id}"

    @property
    def display_name(self):
        if self.user_id:
            return self.user.name or self.user.email.split("@")[0]
        return self.guest_name or "Guest"

    @property
    def amount_due(self):
        return self.share_due + self.fee_due

    @property
    def amount_paid(self):
        return self.share_paid + self.fee_paid


class JoinRequest(TimeStamped):
    """A solo player's request: a private 1-on-1 thread with the host until approved or declined."""
    STATUS = [("pending", "Pending"), ("approved", "Approved"), ("declined", "Declined"), ("withdrawn", "Withdrawn")]
    lobby = models.ForeignKey(Lobby, on_delete=models.CASCADE, related_name="requests")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="lobby_requests")
    status = models.CharField(max_length=10, choices=STATUS, default="pending")
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        unique_together = ("lobby", "user")


class LobbyMessage(models.Model):
    """Match Room chat when `request` is empty, otherwise the 1-on-1 screening thread."""
    KINDS = [("text", "Text"), ("system", "System"), ("payment", "Payment card")]
    lobby = models.ForeignKey(Lobby, on_delete=models.CASCADE, related_name="messages")
    request = models.ForeignKey(JoinRequest, null=True, blank=True, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                               related_name="+")
    kind = models.CharField(max_length=8, choices=KINDS, default="text")
    body = models.CharField(max_length=500)
    member = models.ForeignKey(LobbyMember, null=True, blank=True, on_delete=models.CASCADE, related_name="+",
                               help_text="Who a payment card is for")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["id"]
