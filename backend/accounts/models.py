import hashlib
import random
import secrets
import string

from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra):
        if not email:
            raise ValueError("Email is required")
        user = self.model(email=normalize_email(email), **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        return self.create_user(email, password, **extra)


def normalize_email(email):
    return str(email or "").strip().lower()


def normalize_phone(phone):
    digits = "".join(ch for ch in str(phone) if ch.isdigit())
    if len(digits) == 10:
        digits = "91" + digits
    return "+" + digits


def make_referral_code():
    alphabet = string.ascii_uppercase + string.digits
    return "PLAY-" + "".join(secrets.choice(alphabet) for _ in range(4))


class User(AbstractBaseUser, PermissionsMixin):
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=80, blank=True)
    phone = models.CharField(max_length=16, blank=True, help_text="Contact number shared with the venue you book")
    address = models.CharField(max_length=255, blank=True, help_text="Optional")
    handle = models.CharField(max_length=40, blank=True, help_text="Shown as @handle")
    avatar = models.ImageField(upload_to="avatars/", blank=True)
    home_area = models.ForeignKey("venues.Area", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    lat = models.FloatField(null=True, blank=True)
    lng = models.FloatField(null=True, blank=True)

    show_to_nearby = models.BooleanField(default=True)
    notifications_on = models.BooleanField(default=True)
    slot_alerts_on = models.BooleanField(default=True)
    referral_code = models.CharField(max_length=12, unique=True, default=make_referral_code)
    referred_by = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="referrals")
    wallet_balance = models.PositiveIntegerField(default=0)

    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False, verbose_name="admin",
                                   help_text="Full access to the admin panel")
    is_venue_owner = models.BooleanField(
        default=False, verbose_name="turf owner",
        help_text="Can sign in to the admin panel to manage only the venues they own")
    date_joined = models.DateTimeField(default=timezone.now)

    objects = UserManager()
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    class Meta:
        ordering = ["-date_joined"]

    def __str__(self):
        return self.name or self.email

    @property
    def initials(self):
        parts = [p for p in (self.name or "").split() if p]
        if not parts:
            return "ME"
        return "".join(p[0] for p in parts[:2]).upper()

    @property
    def masked_email(self):
        """arjun.mehta@gmail.com -> ar•••••••@gmail.com"""
        local, _, domain = self.email.partition("@")
        keep = local[:2]
        return f"{keep}{'•' * max(3, len(local) - len(keep))}@{domain}"

    @property
    def masked_phone(self):
        p = self.phone
        if len(p) < 8:
            return p
        # +91 98••• ••521
        local = p[-10:]
        return f"{p[:-10]} {local[:2]}••• ••{local[-3:]}"

    @property
    def can_use_panel(self):
        return self.is_active and (self.is_staff or self.is_venue_owner)

    def get_full_name(self):
        return self.name

    def get_short_name(self):
        return self.name.split(" ")[0] if self.name else self.email.split("@")[0]


class PlayerSport(models.Model):
    LEVELS = [(0, "Beginner"), (1, "Intermediate"), (2, "Advanced")]
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sports")
    sport = models.ForeignKey("venues.Sport", on_delete=models.CASCADE)
    level = models.PositiveSmallIntegerField(choices=LEVELS, default=0)

    class Meta:
        unique_together = ("user", "sport")
        ordering = ["-level", "sport__order"]

    def __str__(self):
        return f"{self.user} · {self.sport} · {self.get_level_display()}"


class EmailOTP(models.Model):
    email = models.EmailField(db_index=True)
    code_hash = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)
    attempts = models.PositiveSmallIntegerField(default=0)
    used = models.BooleanField(default=False)

    TTL_SECONDS = 600
    RESEND_SECONDS = 30
    MAX_ATTEMPTS = 5

    class Meta:
        ordering = ["-created_at"]

    @staticmethod
    def hash(code):
        return hashlib.sha256(code.encode()).hexdigest()

    @classmethod
    def issue(cls, email, dev_mode=False):
        code = "123456" if dev_mode else f"{random.SystemRandom().randint(0, 999999):06d}"
        cls.objects.filter(email=email, used=False).update(used=True)
        cls.objects.create(email=email, code_hash=cls.hash(code))
        return code

    @classmethod
    def recently_sent(cls, email):
        last = cls.objects.filter(email=email).first()
        return bool(last and (timezone.now() - last.created_at).total_seconds() < cls.RESEND_SECONDS)

    def is_expired(self):
        return (timezone.now() - self.created_at).total_seconds() > self.TTL_SECONDS
