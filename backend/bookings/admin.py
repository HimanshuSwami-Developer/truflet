from django.contrib import admin

from .models import Booking, Coupon


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("code", "user", "venue", "date", "start_hour", "status", "total")
    list_filter = ("status", "payment_status")
    search_fields = ("code", "user__email")


admin.site.register(Coupon)
