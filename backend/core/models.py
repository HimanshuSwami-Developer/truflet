from django.conf import settings
from django.db import models


class TimeStamped(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class AppConfig(models.Model):
    """Singleton with business settings editable from the admin panel."""

    convenience_fee = models.PositiveIntegerField(default=40, help_text="₹ per booking")
    gst_percent = models.DecimalField(max_digits=5, decimal_places=2, default=18, help_text="GST on the convenience fee")
    hold_minutes = models.PositiveIntegerField(default=10, help_text="How long a slot is held while paying")
    free_cancel_hours = models.PositiveIntegerField(default=6)
    reschedule_cutoff_hours = models.PositiveIntegerField(default=2)
    max_reschedules = models.PositiveIntegerField(default=1)
    referral_reward = models.PositiveIntegerField(default=50)
    split_fee = models.PositiveIntegerField(default=15, help_text="₹ platform fee on each split payment in a match")

    offer_enabled = models.BooleanField(default=True)
    offer_tag = models.CharField(max_length=40, default="WEEKEND OFFER")
    offer_title = models.CharField(max_length=80, default="₹100 off your\nfirst booking")
    offer_subtitle = models.CharField(max_length=80, default="Use code PLAY100")
    offer_image = models.ImageField(upload_to="offers/", blank=True)

    support_phone = models.CharField(max_length=20, default="+918000000000")
    support_email = models.EmailField(default="support@turflet.app")
    support_whatsapp = models.CharField(max_length=20, blank=True)
    chat_hours = models.CharField(max_length=40, default="24 × 7")
    call_hours = models.CharField(max_length=40, default="9 AM – 11 PM")
    email_sla = models.CharField(max_length=40, default="In 24 hrs")
    reply_time_text = models.CharField(max_length=80, default="We usually reply in under 5 minutes.")
    policy_updated_on = models.DateField(null=True, blank=True)
    app_version = models.CharField(max_length=20, default="1.1")

    class Meta:
        verbose_name = "App settings"
        verbose_name_plural = "App settings"

    def __str__(self):
        return "App settings"

    def save(self, *args, **kwargs):
        self.pk = 1
        super().save(*args, **kwargs)

    @classmethod
    def get(cls):
        obj, _ = cls.objects.get_or_create(pk=1)
        return obj


class FAQ(models.Model):
    question = models.CharField(max_length=200)
    answer = models.TextField()
    order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["order", "id"]
        verbose_name = "FAQ"

    def __str__(self):
        return self.question


class RefundRule(models.Model):
    """Refund tiers, used both for display and for the actual refund calculation."""

    min_hours_before = models.PositiveIntegerField(help_text="Applies when at least this many hours are left")
    percent = models.PositiveIntegerField(help_text="% of slot charges refunded")
    title = models.CharField(max_length=80)
    subtitle = models.CharField(max_length=120)

    class Meta:
        ordering = ["-min_hours_before"]

    def __str__(self):
        return f"{self.percent}% ≥ {self.min_hours_before}h"

    @classmethod
    def percent_for(cls, hours_left):
        for rule in cls.objects.all():
            if hours_left >= rule.min_hours_before:
                return rule.percent
        return 0


class PolicySection(models.Model):
    KIND_CHOICES = [
        ("refund_note", "Refund · good to know"),
        ("privacy", "Privacy"),
        ("terms", "Terms of use"),
    ]
    ICON_CHOICES = [
        ("clock", "Clock"), ("refresh", "Refresh"), ("cloud", "Cloud / rain"), ("receipt", "Receipt"),
        ("shield", "Shield"), ("info", "Info"),
    ]
    COLOR_CHOICES = [
        ("blue", "Blue"), ("purple", "Purple"), ("teal", "Teal"), ("gray", "Gray"),
        ("green", "Green"), ("amber", "Amber"), ("orange", "Orange"),
    ]
    kind = models.CharField(max_length=20, choices=KIND_CHOICES)
    heading = models.CharField(max_length=120)
    body = models.TextField(help_text="For privacy/terms: one bullet per line. For refund notes: the sentence.")
    icon = models.CharField(max_length=20, choices=ICON_CHOICES, default="info")
    color = models.CharField(max_length=20, choices=COLOR_CHOICES, default="gray")
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["kind", "order", "id"]

    def __str__(self):
        return f"{self.get_kind_display()} · {self.heading}"

    @property
    def items(self):
        return [line.strip() for line in self.body.splitlines() if line.strip()]


class SupportTicket(TimeStamped):
    STATUS = [("open", "Open"), ("replied", "Replied"), ("closed", "Closed")]
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="tickets")
    booking = models.ForeignKey("bookings.Booking", null=True, blank=True, on_delete=models.SET_NULL)
    subject = models.CharField(max_length=120)
    message = models.TextField()
    reply = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=STATUS, default="open")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"#{self.pk} {self.subject}"


class Notification(TimeStamped):
    KIND = [
        ("booking", "Booking"), ("match", "Match"), ("offer", "Offer"), ("system", "System"),
    ]
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=20, choices=KIND, default="system")
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=255, blank=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title


class DeviceToken(TimeStamped):
    """An FCM registration token for push notifications. One row per device: signing in on a
    device moves its token to the new player."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="devices")
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=20, blank=True)

    def __str__(self):
        return f"{self.user} · {self.platform}"


def notify(user, title, body="", kind="system"):
    """Saves an in-app notification and, once the transaction commits, pushes it to the player's devices."""
    if user is None:
        return None
    n = Notification.objects.create(user=user, title=title, body=body, kind=kind)
    if getattr(user, "notifications_on", True):
        from django.db import transaction

        from .push import send_push

        transaction.on_commit(lambda: send_push(n))
    return n
