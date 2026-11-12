from django.contrib import admin

from .models import EmailOTP, PlayerSport, User


@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ("email", "name", "phone", "is_staff", "is_active", "date_joined")
    search_fields = ("email", "name", "phone")


admin.site.register([PlayerSport, EmailOTP])
