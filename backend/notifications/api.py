"""HTTP API of the notifications service (same paths as before: /notifications/, /devices/)."""
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from . import service
from .models import Notification


@api_view(["GET"])
@permission_classes([permissions.IsAuthenticated])
def notifications(request):
    mine = Notification.objects.filter(user_id=request.user.pk)
    return Response({
        "unread": mine.filter(is_read=False).count(),
        "items": [
            {"id": n.id, "kind": n.kind, "title": n.title, "body": n.body, "is_read": n.is_read,
             "created_at": n.created_at.isoformat()} for n in mine[:50]
        ],
    })


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def notifications_read(request):
    Notification.objects.filter(user_id=request.user.pk, is_read=False).update(is_read=True)
    return Response({"ok": True})


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def devices(request):
    """Registers this device's FCM token for the signed-in player (moves it from any previous player)."""
    token = str(request.data.get("token") or "").strip()
    if not token or len(token) > 512:
        return Response({"message": "A device token is required."}, status=status.HTTP_400_BAD_REQUEST)
    service.register_device(request.user.pk, token, str(request.data.get("platform") or ""))
    return Response({"ok": True})


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
def devices_remove(request):
    """Stops pushes to a device. Open (no session needed) so it works right after sign-out;
    knowing the token is what proves it's this device."""
    service.unregister_device(str(request.data.get("token") or "").strip())
    return Response({"ok": True})
