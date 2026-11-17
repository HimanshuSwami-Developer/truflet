"""Data owned by the notifications service.

The tables keep their original names (they used to live in `core`), so moving the models here
needed no data migration.
"""
from django.conf import settings
from django.db import models


class Notification(models.Model):
    KIND = [
        ("booking", "Booking"), ("match", "Match"), ("offer", "Offer"), ("system", "System"),
    ]
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=20, choices=KIND, default="system")
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=255, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "core_notification"
        ordering = ["-created_at"]

    def __str__(self):
        return self.title


class DeviceToken(models.Model):
    """An FCM registration token for push notifications. One row per device: signing in on a
    device moves its token to the new player."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="devices")
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=20, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "core_devicetoken"

    def __str__(self):
        return f"{self.user} · {self.platform}"
