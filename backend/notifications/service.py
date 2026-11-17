"""The notifications service's public interface — the only module other apps import.

    from notifications import service as notifications
    notifications.notify(booking.user_id, "Booking confirmed", "Arena · Fri, 20 Nov", kind="booking")

Everything crosses this boundary as plain values (ids, strings, lists), never model instances, so
the implementation can move behind HTTP or a message queue later. To do that, write a class with
the same methods as `NotificationService` (e.g. one that POSTs to the new service) and point
`NOTIFICATION_SERVICE` in settings at it; callers don't change.
"""
from importlib import import_module
from typing import Iterable, Protocol

from django.conf import settings
from django.db import transaction

KINDS = ("booking", "match", "offer", "system")


class NotificationService(Protocol):
    def notify(self, user_id: int, title: str, body: str = "", kind: str = "system") -> int | None:
        """Saves an in-app notification and pushes it to the player's devices (unless they muted
        notifications). Returns the notification id, or None when `user_id` is empty."""

    def broadcast(self, user_ids: Iterable[int], title: str, body: str = "", kind: str = "offer") -> int:
        """Saves the same in-app notification for many players. Returns how many were created."""

    def register_device(self, user_id: int, token: str, platform: str = "") -> None:
        """Links a device's push token to a player (moving it from any previous player)."""

    def unregister_device(self, token: str) -> None:
        """Stops pushes to a device."""


class LocalNotificationService:
    """In-process implementation: writes to this service's own tables and pushes through FCM."""

    def notify(self, user_id, title, body="", kind="system"):
        if not user_id:
            return None
        from django.contrib.auth import get_user_model

        from .models import Notification

        n = Notification.objects.create(user_id=user_id, title=title, body=body, kind=kind)
        muted = get_user_model().objects.filter(pk=user_id, notifications_on=False).exists()
        if not muted:
            from .channels import fcm

            data = {"kind": kind, "notification_id": n.pk}
            # push only once the caller's transaction commits, so a rolled-back action never alerts anyone
            transaction.on_commit(lambda: fcm.send(user_id, title, body, data))
        return n.pk

    def broadcast(self, user_ids, title, body="", kind="offer"):
        from .models import Notification

        rows = [Notification(user_id=uid, title=title, body=body, kind=kind) for uid in user_ids]
        Notification.objects.bulk_create(rows)
        return len(rows)

    def register_device(self, user_id, token, platform=""):
        from .models import DeviceToken

        DeviceToken.objects.update_or_create(token=token, defaults={"user_id": user_id, "platform": platform[:20]})

    def unregister_device(self, token):
        from .models import DeviceToken

        DeviceToken.objects.filter(token=token).delete()


_service = None


def get_service() -> NotificationService:
    """The configured implementation (`NOTIFICATION_SERVICE` = dotted path to a class)."""
    global _service
    if _service is None:
        path = getattr(settings, "NOTIFICATION_SERVICE", "notifications.service.LocalNotificationService")
        module, _, name = path.rpartition(".")
        _service = getattr(import_module(module), name)()
    return _service


# Module-level shortcuts, so call sites read `notifications.notify(...)`.
def notify(user_id, title, body="", kind="system"):
    return get_service().notify(user_id, title, body, kind)


def broadcast(user_ids, title, body="", kind="offer"):
    return get_service().broadcast(user_ids, title, body, kind)


def register_device(user_id, token, platform=""):
    return get_service().register_device(user_id, token, platform)


def unregister_device(token):
    return get_service().unregister_device(token)
