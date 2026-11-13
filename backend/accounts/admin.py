from django.contrib import admin
from django.utils import timezone

from .models import AccountDeletionRequest, EmailOTP, PlayerSport, User


@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ("email", "name", "phone", "is_staff", "is_active", "date_joined")
    search_fields = ("email", "name", "phone")


@admin.register(AccountDeletionRequest)
class AccountDeletionRequestAdmin(admin.ModelAdmin):
    list_display = ("email", "user", "status", "created_at", "processed_at")
    list_filter = ("status",)
    search_fields = ("email",)
    readonly_fields = ("email", "user", "reason", "created_at", "processed_at")

    def save_model(self, request, obj, form, change):
        if obj.status != "pending" and not obj.processed_at:
            obj.processed_at = timezone.now()
        super().save_model(request, obj, form, change)


admin.site.register([PlayerSport, EmailOTP])
