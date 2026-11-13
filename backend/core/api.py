from rest_framework import permissions, serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from .models import FAQ, AppConfig, Notification, PolicySection, RefundRule, SupportTicket


def exception_handler(exc, context):
    """Adds a single human readable `message` to every error response."""
    response = drf_exception_handler(exc, context)
    if response is not None and isinstance(response.data, (dict, list)):
        response.data = {"message": _first_message(response.data), "errors": response.data}
    return response


def _first_message(data):
    if isinstance(data, list):
        return _first_message(data[0]) if data else "Something went wrong."
    if isinstance(data, dict):
        if "detail" in data:
            return str(data["detail"])
        for v in data.values():
            return _first_message(v)
    return str(data)


def image_url(request, field):
    """Absolute URL for an ImageField (works for local files and Cloudinary)."""
    if not field:
        return None
    try:
        url = field.url
    except ValueError:
        return None
    if url.startswith("http"):
        return url
    return request.build_absolute_uri(url) if request else url


class ImageURLField(serializers.Field):
    def to_representation(self, value):
        return image_url(self.context.get("request"), value)


# ------------------------------------------------------------------ config & content

@api_view(["GET"])
def app_config(request):
    from venues.models import Venue
    c = AppConfig.get()
    return Response({
        "convenience_fee": c.convenience_fee,
        "gst_percent": float(c.gst_percent),
        "hold_minutes": c.hold_minutes,
        "free_cancel_hours": c.free_cancel_hours,
        "reschedule_cutoff_hours": c.reschedule_cutoff_hours,
        "referral_reward": c.referral_reward,
        "split_fee": c.split_fee,
        "live_venues": Venue.objects.filter(is_active=True).count(),
        "offer": {
            "enabled": c.offer_enabled, "tag": c.offer_tag, "title": c.offer_title,
            "subtitle": c.offer_subtitle, "image": image_url(request, c.offer_image),
        },
        "support": {
            "phone": c.support_phone, "email": c.support_email, "whatsapp": c.support_whatsapp,
            "chat_hours": c.chat_hours, "call_hours": c.call_hours, "email_sla": c.email_sla,
            "reply_time": c.reply_time_text,
        },
        "policy_updated_on": c.policy_updated_on.strftime("%-d %b %Y") if c.policy_updated_on else None,
        "app_version": c.app_version,
    })


@api_view(["GET"])
def faqs(request):
    q = request.GET.get("q", "").strip()
    qs = FAQ.objects.filter(is_active=True)
    if q:
        from django.db.models import Q
        qs = qs.filter(Q(question__icontains=q) | Q(answer__icontains=q))
    return Response([{"id": f.id, "q": f.question, "a": f.answer} for f in qs])


@api_view(["GET"])
def policies(request):
    sections = PolicySection.objects.all()
    return Response({
        "refund_rules": [
            {"percent": r.percent, "min_hours": r.min_hours_before, "title": r.title, "subtitle": r.subtitle}
            for r in RefundRule.objects.all()
        ],
        "refund_notes": [
            {"heading": s.heading, "body": s.body, "icon": s.icon, "color": s.color}
            for s in sections if s.kind == "refund_note"
        ],
        "privacy": [{"heading": s.heading, "items": s.items} for s in sections if s.kind == "privacy"],
        "terms": [{"heading": s.heading, "items": s.items} for s in sections if s.kind == "terms"],
    })


# ------------------------------------------------------------------ notifications & support

@api_view(["GET"])
@permission_classes([permissions.IsAuthenticated])
def notifications(request):
    qs = request.user.notifications.all()[:50]
    return Response({
        "unread": request.user.notifications.filter(is_read=False).count(),
        "items": [
            {"id": n.id, "kind": n.kind, "title": n.title, "body": n.body, "is_read": n.is_read,
             "created_at": n.created_at.isoformat()} for n in qs
        ],
    })


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def notifications_read(request):
    request.user.notifications.filter(is_read=False).update(is_read=True)
    return Response({"ok": True})


class TicketSerializer(serializers.ModelSerializer):
    class Meta:
        model = SupportTicket
        fields = ["id", "booking", "subject", "message", "reply", "status", "created_at"]
        read_only_fields = ["reply", "status", "created_at"]


@api_view(["GET", "POST"])
@permission_classes([permissions.IsAuthenticated])
def tickets(request):
    if request.method == "POST":
        s = TicketSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        booking = s.validated_data.get("booking")
        if booking and booking.user_id != request.user.id:
            return Response({"message": "Not your booking."}, status=status.HTTP_400_BAD_REQUEST)
        s.save(user=request.user)
        return Response(s.data, status=status.HTTP_201_CREATED)
    return Response(TicketSerializer(request.user.tickets.all(), many=True).data)
