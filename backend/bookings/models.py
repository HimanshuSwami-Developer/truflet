import secrets
from datetime import datetime, timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from core.models import TimeStamped


class Coupon(TimeStamped):
    TYPES = [("flat", "Flat ₹"), ("percent", "Percent %")]
    code = models.CharField(max_length=20, unique=True)
    description = models.CharField(max_length=120, blank=True)
    discount_type = models.CharField(max_length=10, choices=TYPES, default="flat")
    value = models.PositiveIntegerField(help_text="₹ amount or % depending on type")
    max_discount = models.PositiveIntegerField(null=True, blank=True, help_text="Cap for % coupons")
    min_amount = models.PositiveIntegerField(default=0)
    first_booking_only = models.BooleanField(default=False)
    valid_from = models.DateTimeField(null=True, blank=True)
    valid_to = models.DateTimeField(null=True, blank=True)
    usage_limit = models.PositiveIntegerField(null=True, blank=True, help_text="Total uses allowed")
    per_user_limit = models.PositiveIntegerField(default=1)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.code

    def save(self, *args, **kwargs):
        self.code = self.code.strip().upper()
        super().save(*args, **kwargs)

    def discount_for(self, amount):
        if self.discount_type == "percent":
            d = amount * self.value // 100
            if self.max_discount:
                d = min(d, self.max_discount)
        else:
            d = self.value
        return min(d, amount)

    def validate(self, user, amount):
        """Return an error message, or None when usable."""
        now = timezone.now()
        if not self.is_active:
            return "This coupon is no longer active."
        if self.valid_from and now < self.valid_from:
            return "This coupon is not active yet."
        if self.valid_to and now > self.valid_to:
            return "This coupon has expired."
        if amount < self.min_amount:
            return f"Minimum booking value is ₹{self.min_amount}."
        used = Booking.objects.filter(coupon=self, payment_status="paid")
        if self.usage_limit is not None and used.count() >= self.usage_limit:
            return "This coupon has been fully used."
        if user and used.filter(user=user).count() >= self.per_user_limit:
            return "You have already used this coupon."
        if self.first_booking_only and user and Booking.objects.filter(user=user, payment_status="paid").exists():
            return "This coupon is for your first booking only."
        return None


def make_booking_code(prefix="TRF"):
    """e.g. TRF-7N26-4821 (day, month initial, year, random)."""
    d = timezone.localdate()
    return f"{prefix}-{d.day}{d.strftime('%b')[0]}{d.strftime('%y')}-{secrets.randbelow(10000):04d}"


class Booking(TimeStamped):
    STATUS = [
        ("held", "Held (awaiting payment)"),
        ("confirmed", "Confirmed"),
        ("completed", "Completed"),
        ("cancelled", "Cancelled"),
        ("expired", "Expired"),
    ]
    PAYMENT_STATUS = [("pending", "Pending"), ("paid", "Paid"), ("refunded", "Refunded"), ("failed", "Failed")]
    METHODS = [("upi", "UPI"), ("card", "Card"), ("net", "Net banking"), ("wallet", "Wallet"), ("venue", "At venue")]

    code = models.CharField(max_length=20, unique=True, default=make_booking_code)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="bookings")
    venue = models.ForeignKey("venues.Venue", on_delete=models.PROTECT, related_name="bookings")
    court = models.ForeignKey("venues.Court", on_delete=models.PROTECT, related_name="bookings")
    sport = models.ForeignKey("venues.Sport", on_delete=models.PROTECT, related_name="bookings")
    date = models.DateField()
    start_hour = models.PositiveSmallIntegerField()
    duration = models.PositiveSmallIntegerField(default=1)
    players = models.PositiveIntegerField(default=16)

    slot_amount = models.PositiveIntegerField(default=0)
    peak_hours = models.PositiveSmallIntegerField(default=0)
    convenience_fee = models.PositiveIntegerField(default=0)
    gst = models.PositiveIntegerField(default=0)
    coupon = models.ForeignKey(Coupon, null=True, blank=True, on_delete=models.SET_NULL, related_name="bookings")
    discount = models.PositiveIntegerField(default=0)
    total = models.PositiveIntegerField(default=0)

    status = models.CharField(max_length=12, choices=STATUS, default="held", db_index=True)
    payment_status = models.CharField(max_length=10, choices=PAYMENT_STATUS, default="pending")
    payment_method = models.CharField(max_length=10, choices=METHODS, blank=True)
    upi_id = models.CharField(max_length=60, blank=True)
    transaction_id = models.CharField(max_length=60, blank=True)
    paid_at = models.DateTimeField(null=True, blank=True)
    held_until = models.DateTimeField(null=True, blank=True)

    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancellation_code = models.CharField(max_length=20, blank=True)
    cancel_reason = models.CharField(max_length=120, blank=True)
    refund_amount = models.PositiveIntegerField(default=0)
    refunded_at = models.DateTimeField(null=True, blank=True)

    checked_in_at = models.DateTimeField(null=True, blank=True)
    reschedule_count = models.PositiveSmallIntegerField(default=0)
    notes = models.TextField(blank=True, help_text="Internal notes")

    class Meta:
        ordering = ["-date", "-start_hour"]
        indexes = [models.Index(fields=["court", "date"])]

    def __str__(self):
        return self.code

    def save(self, *args, **kwargs):
        if self._state.adding:
            while Booking.objects.filter(code=self.code).exists():
                self.code = make_booking_code()
        super().save(*args, **kwargs)

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
    def hours_left(self):
        return (self.start_dt - timezone.now()).total_seconds() / 3600

    def blocks_slot(self):
        if self.status == "confirmed":
            return True
        return self.status == "held" and self.held_until and self.held_until > timezone.now()

    @classmethod
    def sync_statuses(cls, qs=None):
        """Expire stale holds and complete past bookings."""
        qs = qs if qs is not None else cls.objects.all()
        now = timezone.now()
        qs.filter(status="held", held_until__lt=now).update(status="expired")
        today = timezone.localdate()
        hour = timezone.localtime().hour
        for b in qs.filter(status="confirmed", date__lte=today).only("id", "date", "start_hour", "duration"):
            if b.date < today or b.start_hour + b.duration <= hour:
                cls.objects.filter(pk=b.pk).update(status="completed")


def make_txn_id(method):
    return f"{method.upper()}/{secrets.randbelow(10000):04d}/{secrets.randbelow(10000):04d}/{secrets.randbelow(10000):04d}"
