import math

from django.conf import settings
from django.db import models
from django.utils.text import slugify

from core.models import TimeStamped


class City(models.Model):
    name = models.CharField(max_length=60, unique=True)
    order = models.PositiveIntegerField(default=0)
    is_popular = models.BooleanField(default=True)

    class Meta:
        ordering = ["order", "name"]
        verbose_name_plural = "cities"

    def __str__(self):
        return self.name


class Area(models.Model):
    city = models.ForeignKey(City, on_delete=models.CASCADE, related_name="areas")
    name = models.CharField(max_length=80)
    pincode = models.CharField(max_length=10, blank=True)
    lat = models.FloatField(null=True, blank=True)
    lng = models.FloatField(null=True, blank=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["city__order", "order", "name"]
        unique_together = ("city", "name")

    def __str__(self):
        return f"{self.name}, {self.city.name}"


class Sport(models.Model):
    SCORING = [("cricket", "Cricket (runs / wickets / overs)"), ("points", "Points / goals")]
    name = models.CharField(max_length=40, unique=True)
    slug = models.SlugField(max_length=40, unique=True, blank=True)
    fg_color = models.CharField(max_length=7, default="#15803D", help_text="Text colour, e.g. #15803D")
    bg_color = models.CharField(max_length=7, default="#DCFCE7", help_text="Chip background, e.g. #DCFCE7")
    image = models.ImageField(upload_to="sports/", blank=True)
    match_minutes = models.PositiveIntegerField(default=60, help_text="Typical tournament match length")
    team_size = models.PositiveIntegerField(default=8)
    scoring = models.CharField(max_length=10, choices=SCORING, default="points")
    order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["order", "name"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.name)
        super().save(*args, **kwargs)


class Amenity(models.Model):
    ICONS = [
        ("parking", "Parking"), ("floodlights", "Floodlights"), ("washroom", "Washroom"),
        ("water", "Drinking water"), ("changing", "Changing room"), ("equipment", "Equipment"),
        ("wifi", "Wi-Fi"), ("cafe", "Cafe"), ("first_aid", "First aid"), ("seating", "Seating"),
    ]
    name = models.CharField(max_length=40, unique=True)
    icon = models.CharField(max_length=20, choices=ICONS, default="equipment")
    fg_color = models.CharField(max_length=7, default="#15803D")
    bg_color = models.CharField(max_length=7, default="#DCFCE7")
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "name"]
        verbose_name_plural = "amenities"

    def __str__(self):
        return self.name


class Venue(TimeStamped):
    name = models.CharField(max_length=120)
    slug = models.SlugField(max_length=140, unique=True, blank=True)
    area = models.ForeignKey(Area, on_delete=models.PROTECT, related_name="venues")
    address = models.CharField(max_length=255)
    lat = models.FloatField(null=True, blank=True)
    lng = models.FloatField(null=True, blank=True)
    phone = models.CharField(max_length=20, blank=True)
    about = models.TextField(blank=True)
    rules = models.TextField(blank=True, help_text="One rule per line")
    surface = models.CharField(max_length=60, blank=True, default="Artificial grass")
    size = models.CharField(max_length=60, blank=True, default="100 × 60 ft")
    cover = models.ImageField(upload_to="venues/", blank=True)
    opens_at = models.PositiveSmallIntegerField(default=6, help_text="Hour 0–23")
    closes_at = models.PositiveSmallIntegerField(default=24, help_text="Hour 1–24 (24 = midnight)")
    peak_start = models.PositiveSmallIntegerField(default=18, help_text="First peak hour")
    peak_end = models.PositiveSmallIntegerField(default=21, help_text="Last peak hour (inclusive)")
    rating = models.DecimalField(max_digits=2, decimal_places=1, default=0)
    review_count = models.PositiveIntegerField(default=0)
    is_fast_filling = models.BooleanField(default=False)
    highlight = models.CharField(max_length=30, blank=True, help_text="Small tag, e.g. Floodlit, Covered")
    amenities = models.ManyToManyField(Amenity, blank=True)
    is_active = models.BooleanField(default=True)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL,
                              related_name="owned_venues")

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        if not self.slug:
            base = slugify(self.name)[:120] or "venue"
            slug, n = base, 2
            while Venue.objects.filter(slug=slug).exclude(pk=self.pk).exists():
                slug, n = f"{base}-{n}", n + 1
            self.slug = slug
        super().save(*args, **kwargs)

    @property
    def rule_list(self):
        return [r.strip() for r in self.rules.splitlines() if r.strip()]

    def is_peak(self, hour):
        return self.peak_start <= hour <= self.peak_end

    def distance_km(self, lat, lng):
        if None in (lat, lng, self.lat, self.lng):
            return None
        r = 6371.0
        p1, p2 = math.radians(lat), math.radians(self.lat)
        dp = math.radians(self.lat - lat)
        dl = math.radians(self.lng - lng)
        a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
        return round(2 * r * math.asin(math.sqrt(a)), 1)

    @property
    def price_from(self):
        prices = [vs.base_price for vs in self.venue_sports.all()]
        return min(prices) if prices else 0

    @property
    def hours_label(self):
        def fmt(h):
            h = h % 24
            return f"{(h % 12) or 12} {'AM' if h < 12 else 'PM'}"
        return f"{fmt(self.opens_at)} – {fmt(self.closes_at)}"


class VenuePhoto(models.Model):
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="photos")
    image = models.ImageField(upload_to="venues/")
    caption = models.CharField(max_length=120, blank=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "id"]

    def __str__(self):
        return f"{self.venue} photo {self.pk}"


class VenueSport(models.Model):
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="venue_sports")
    sport = models.ForeignKey(Sport, on_delete=models.CASCADE, related_name="venue_sports")
    meta = models.CharField(max_length=60, blank=True, help_text="e.g. Box · 8-a-side")
    image = models.ImageField(upload_to="venues/", blank=True)
    base_price = models.PositiveIntegerField(help_text="₹ per hour")
    peak_surcharge = models.PositiveIntegerField(default=300, help_text="₹ added per peak hour")
    max_players = models.PositiveIntegerField(default=16)

    class Meta:
        unique_together = ("venue", "sport")
        ordering = ["sport__order"]

    def __str__(self):
        return f"{self.venue} · {self.sport}"

    def price_for(self, hour):
        return self.base_price + (self.peak_surcharge if self.venue.is_peak(hour) else 0)


class Court(models.Model):
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="courts")
    name = models.CharField(max_length=40)
    meta = models.CharField(max_length=60, blank=True, help_text="e.g. Box · 8-a-side")
    sports = models.ManyToManyField(Sport, related_name="courts")
    order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["order", "name"]

    def __str__(self):
        return f"{self.venue} · {self.name}"


class BlockedSlot(models.Model):
    """Maintenance / offline bookings entered by the venue."""

    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="blocked_slots")
    court = models.ForeignKey(Court, null=True, blank=True, on_delete=models.CASCADE,
                              help_text="Leave empty to block every court")
    date = models.DateField()
    start_hour = models.PositiveSmallIntegerField()
    end_hour = models.PositiveSmallIntegerField(help_text="Exclusive, e.g. 20 blocks until 8 PM")
    reason = models.CharField(max_length=120, blank=True)

    class Meta:
        ordering = ["-date", "start_hour"]

    def __str__(self):
        return f"{self.venue} {self.date} {self.start_hour}-{self.end_hour}"


class SavedVenue(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="saved_venues")
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="saved_by")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("user", "venue")
        ordering = ["-created_at"]


class Review(TimeStamped):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reviews")
    venue = models.ForeignKey(Venue, on_delete=models.CASCADE, related_name="reviews")
    booking = models.OneToOneField("bookings.Booking", null=True, blank=True, on_delete=models.SET_NULL,
                                   related_name="review")
    rating = models.PositiveSmallIntegerField()
    comment = models.TextField(blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.venue} · {self.rating}★"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        agg = self.venue.reviews.aggregate(avg=models.Avg("rating"), n=models.Count("id"))
        Venue.objects.filter(pk=self.venue_id).update(rating=round(agg["avg"] or 0, 1), review_count=agg["n"])
