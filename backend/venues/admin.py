from django.contrib import admin

from .models import Amenity, Area, BlockedSlot, City, Court, Review, SavedVenue, Sport, Venue, VenuePhoto, VenueSport


class PhotoInline(admin.TabularInline):
    model = VenuePhoto
    extra = 0


class CourtInline(admin.TabularInline):
    model = Court
    extra = 0


class VenueSportInline(admin.TabularInline):
    model = VenueSport
    extra = 0


@admin.register(Venue)
class VenueAdmin(admin.ModelAdmin):
    list_display = ("name", "area", "rating", "is_active")
    inlines = [VenueSportInline, CourtInline, PhotoInline]


admin.site.register([City, Area, Sport, Amenity, BlockedSlot, SavedVenue, Review])
