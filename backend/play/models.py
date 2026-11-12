import secrets

from django.conf import settings
from django.db import models
from django.db.models import Q
from django.utils.text import slugify

from core.models import TimeStamped

User = settings.AUTH_USER_MODEL


def unique_slug(model, text, field="slug"):
    base = slugify(text)[:60] or "item"
    slug, n = base, 2
    while model.objects.filter(**{field: slug}).exists():
        slug, n = f"{base}-{n}", n + 1
    return slug


# ------------------------------------------------------------------ squad

class Group(TimeStamped):
    name = models.CharField(max_length=80)
    slug = models.SlugField(max_length=80, unique=True, blank=True, help_text="Used in the invite link")
    sport = models.ForeignKey("venues.Sport", on_delete=models.PROTECT, related_name="groups")
    area = models.ForeignKey("venues.Area", null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    image = models.ImageField(upload_to="groups/", blank=True)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name="created_groups")
    members = models.ManyToManyField(User, through="GroupMember", related_name="squad_groups")

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = unique_slug(Group, self.name)
        super().save(*args, **kwargs)


class GroupMember(models.Model):
    ROLES = [("admin", "Admin"), ("member", "Member")]
    group = models.ForeignKey(Group, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=10, choices=ROLES, default="member")
    position = models.CharField(max_length=40, blank=True, help_text="e.g. Captain, Wicket-keeper")
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("group", "user")
        ordering = ["-role", "joined_at"]


class FriendRequest(TimeStamped):
    STATUS = [("pending", "Pending"), ("accepted", "Accepted"), ("declined", "Declined")]
    from_user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sent_requests")
    to_user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="received_requests")
    status = models.CharField(max_length=10, choices=STATUS, default="pending")

    class Meta:
        unique_together = ("from_user", "to_user")
        ordering = ["-created_at"]

    @staticmethod
    def friends_of(user):
        from accounts.models import User as U
        accepted = FriendRequest.objects.filter(status="accepted").filter(Q(from_user=user) | Q(to_user=user))
        ids = set()
        for fr in accepted.values_list("from_user_id", "to_user_id"):
            ids.update(fr)
        ids.discard(user.id)
        return U.objects.filter(id__in=ids)


# ------------------------------------------------------------------ games (quick matches & group games)

class Game(TimeStamped):
    STATUS = [("upcoming", "Upcoming"), ("completed", "Completed"), ("cancelled", "Cancelled")]
    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True, blank=True)
    sport = models.ForeignKey("venues.Sport", on_delete=models.PROTECT)
    group = models.ForeignKey(Group, null=True, blank=True, on_delete=models.SET_NULL, related_name="games")
    venue = models.ForeignKey("venues.Venue", on_delete=models.PROTECT, related_name="games")
    court = models.ForeignKey("venues.Court", null=True, blank=True, on_delete=models.SET_NULL)
    booking = models.ForeignKey("bookings.Booking", null=True, blank=True, on_delete=models.SET_NULL, related_name="games")
    date = models.DateField()
    start_hour = models.PositiveSmallIntegerField()
    duration = models.PositiveSmallIntegerField(default=1)
    per_side = models.PositiveSmallIntegerField(default=8)
    auto_balance = models.BooleanField(default=True)
    total_cost = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=10, choices=STATUS, default="upcoming")
    result = models.CharField(max_length=120, blank=True, help_text="e.g. Lost by 12 runs")
    won = models.BooleanField(null=True, blank=True)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name="created_games")

    class Meta:
        ordering = ["date", "start_hour"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = unique_slug(Game, self.name)
        super().save(*args, **kwargs)

    @property
    def in_count(self):
        return self.rsvps.filter(response="in").count()

    @property
    def maybe_count(self):
        return self.rsvps.filter(response="maybe").count()

    @property
    def share(self):
        n = max(1, self.in_count)
        return -(-self.total_cost // n)  # ceil


class RSVP(models.Model):
    RESPONSES = [("in", "Going"), ("maybe", "Maybe"), ("out", "Out"), ("pending", "No reply")]
    game = models.ForeignKey(Game, on_delete=models.CASCADE, related_name="rsvps")
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="rsvps")
    response = models.CharField(max_length=10, choices=RESPONSES, default="pending")
    paid = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("game", "user")


# ------------------------------------------------------------------ tournaments

class Tournament(TimeStamped):
    FORMATS = [("ko", "Knockout"), ("league", "League (round robin)"), ("groups", "Groups + knockout")]
    STATUS = [("draft", "Draft"), ("open", "Registrations open"), ("live", "Live"), ("completed", "Completed")]
    WINDOWS = [("morning", "Morning · 7 AM – 1 PM"), ("full", "Full day · 8 AM – 10 PM"), ("evening", "Evening · 4 PM – 11 PM")]
    WINDOW_HOURS = {"morning": (7, 13), "full": (8, 22), "evening": (16, 23)}

    name = models.CharField(max_length=100)
    slug = models.SlugField(max_length=100, unique=True, blank=True)
    sport = models.ForeignKey("venues.Sport", on_delete=models.PROTECT, related_name="tournaments")
    host = models.ForeignKey(User, on_delete=models.CASCADE, related_name="hosted_tournaments")
    format = models.CharField(max_length=10, choices=FORMATS, default="ko")
    team_count = models.PositiveSmallIntegerField(default=8)
    players_per_team = models.PositiveSmallIntegerField(default=8)
    entry_fee = models.PositiveIntegerField(default=0)
    prize_pool = models.PositiveIntegerField(default=0)
    venue = models.ForeignKey("venues.Venue", on_delete=models.PROTECT, related_name="tournaments")
    start_date = models.DateField()
    window = models.CharField(max_length=10, choices=WINDOWS, default="full")
    overs = models.PositiveSmallIntegerField(default=10, help_text="Cricket only: overs per innings")
    status = models.CharField(max_length=10, choices=STATUS, default="open")
    cover = models.ImageField(upload_to="tournaments/", blank=True)

    class Meta:
        ordering = ["start_date"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = unique_slug(Tournament, self.name)
        super().save(*args, **kwargs)

    @property
    def window_hours(self):
        return self.WINDOW_HOURS[self.window]

    @property
    def collected(self):
        return self.teams.filter(paid=True).count() * self.entry_fee

    @property
    def total_matches(self):
        return self.fixtures.count()

    @property
    def played_matches(self):
        return self.fixtures.filter(state="done").count()


class TournamentTeam(TimeStamped):
    tournament = models.ForeignKey(Tournament, on_delete=models.CASCADE, related_name="teams")
    name = models.CharField(max_length=80)
    captain = models.ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL, related_name="captained_teams")
    captain_name = models.CharField(max_length=80, blank=True)
    group_label = models.CharField(max_length=2, blank=True)
    seed = models.PositiveSmallIntegerField(default=0)
    paid = models.BooleanField(default=False)
    paid_at = models.DateTimeField(null=True, blank=True)
    reminded_at = models.DateTimeField(null=True, blank=True)
    eliminated = models.BooleanField(default=False)

    class Meta:
        ordering = ["seed", "created_at"]
        unique_together = ("tournament", "name")

    def __str__(self):
        return self.name

    @property
    def initials(self):
        return "".join(w[0] for w in self.name.split() if w)[:2].upper()


class Fixture(models.Model):
    STATES = [("tbd", "To be decided"), ("next", "Scheduled"), ("live", "Live"), ("done", "Finished")]
    STAGES = [("ko", "Knockout"), ("league", "League"), ("group", "Group stage")]

    tournament = models.ForeignKey(Tournament, on_delete=models.CASCADE, related_name="fixtures")
    stage = models.CharField(max_length=10, choices=STAGES, default="ko")
    round_index = models.PositiveSmallIntegerField(default=0)
    round_name = models.CharField(max_length=40)
    order = models.PositiveSmallIntegerField(default=0)
    label = models.CharField(max_length=20, blank=True, help_text="e.g. SF1, QF2")
    group_label = models.CharField(max_length=2, blank=True)

    team_a = models.ForeignKey(TournamentTeam, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    team_b = models.ForeignKey(TournamentTeam, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    placeholder_a = models.CharField(max_length=40, blank=True)
    placeholder_b = models.CharField(max_length=40, blank=True)
    next_fixture = models.ForeignKey("self", null=True, blank=True, on_delete=models.SET_NULL, related_name="feeders")
    next_slot = models.CharField(max_length=1, blank=True, choices=[("a", "A"), ("b", "B")])

    court_label = models.CharField(max_length=40, blank=True)
    scheduled_at = models.DateTimeField(null=True, blank=True)
    state = models.CharField(max_length=5, choices=STATES, default="tbd")

    # scores (cricket uses runs/wkts/balls, other sports use runs as points)
    a_runs = models.PositiveIntegerField(default=0)
    a_wkts = models.PositiveSmallIntegerField(default=0)
    a_balls = models.PositiveSmallIntegerField(default=0)
    b_runs = models.PositiveIntegerField(default=0)
    b_wkts = models.PositiveSmallIntegerField(default=0)
    b_balls = models.PositiveSmallIntegerField(default=0)
    batting_first = models.CharField(max_length=1, default="a")
    innings = models.PositiveSmallIntegerField(default=1)
    history = models.JSONField(default=list, blank=True)

    winner = models.ForeignKey(TournamentTeam, null=True, blank=True, on_delete=models.SET_NULL, related_name="+")
    result_text = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["round_index", "order"]

    def __str__(self):
        return f"{self.tournament} · {self.round_name} · {self.label or self.order}"

    @property
    def name_a(self):
        return self.team_a.name if self.team_a else (self.placeholder_a or "TBD")

    @property
    def name_b(self):
        return self.team_b.name if self.team_b else (self.placeholder_b or "TBD")


def invite_token():
    return secrets.token_urlsafe(6)
