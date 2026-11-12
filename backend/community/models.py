"""Playing together: private groups (book a slot, members get invited) and open games
(book a slot, strangers join and pay their share)."""
import math
import secrets
import string

from django.conf import settings
from django.db import models

from core.models import TimeStamped


def make_invite_code():
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(6))


class PlayerGroup(TimeStamped):
    name = models.CharField(max_length=60)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="created_groups")
    invite_code = models.CharField(max_length=12, unique=True, default=make_invite_code,
                                   help_text="Anyone with this code can join from the app")
    members = models.ManyToManyField(settings.AUTH_USER_MODEL, through="GroupMembership", related_name="player_groups")

    class Meta:
        ordering = ["name"]
        verbose_name = "group"

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if self._state.adding:
            while PlayerGroup.objects.filter(invite_code=self.invite_code).exists():
                self.invite_code = make_invite_code()
        super().save(*args, **kwargs)


class GroupMembership(models.Model):
    ROLES = [("admin", "Admin"), ("member", "Member")]
    group = models.ForeignKey(PlayerGroup, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="group_memberships")
    role = models.CharField(max_length=10, choices=ROLES, default="member")
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("group", "user")
        ordering = ["-role", "joined_at"]


class GroupInvite(TimeStamped):
    """Someone added by email / phone who isn't on Turflet yet. Claimed automatically when they sign in."""
    group = models.ForeignKey(PlayerGroup, on_delete=models.CASCADE, related_name="invites")
    contact = models.CharField(max_length=120, help_text="Lower-case email or +91 phone")
    invited_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        unique_together = ("group", "contact")


class GroupGame(models.Model):
    """A booking made for a group: members are notified once it's paid."""
    booking = models.OneToOneField("bookings.Booking", on_delete=models.CASCADE, related_name="group_game")
    group = models.ForeignKey(PlayerGroup, on_delete=models.CASCADE, related_name="games")

    def __str__(self):
        return f"{self.group} · {self.booking}"


class OpenGame(TimeStamped):
    """A booking with spots published to players in the city. The host pays the slot; each player who
    joins pays a share, which is credited to the host's wallet. For a group game, the group's members
    already hold [reserved_spots] and only the rest are public."""
    booking = models.OneToOneField("bookings.Booking", on_delete=models.CASCADE, related_name="open_game")
    total_players = models.PositiveSmallIntegerField(help_text="Including the host")
    reserved_spots = models.PositiveSmallIntegerField(default=1, help_text="Taken before publishing: host, or the whole group")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Open game · {self.booking}"

    @property
    def share(self):
        """What each joining player pays (₹, rounded up)."""
        return math.ceil(self.booking.total / max(1, self.total_players))

    def active_players(self):
        return self.players.filter(status="joined")

    @property
    def spots_left(self):
        return max(0, self.total_players - self.reserved_spots - self.active_players().count())

    @property
    def taken(self):
        return self.reserved_spots + self.active_players().count()


class OpenGamePlayer(TimeStamped):
    STATUS = [("joined", "Joined"), ("left", "Left"), ("refunded", "Refunded")]
    game = models.ForeignKey(OpenGame, on_delete=models.CASCADE, related_name="players")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="open_games_joined")
    amount = models.PositiveIntegerField()
    payment_method = models.CharField(max_length=10, blank=True)
    transaction_id = models.CharField(max_length=60, blank=True)
    status = models.CharField(max_length=10, choices=STATUS, default="joined")

    class Meta:
        unique_together = ("game", "user")
        ordering = ["created_at"]
