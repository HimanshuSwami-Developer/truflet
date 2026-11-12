from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email
from django.db.models import Sum
from rest_framework import permissions, serializers
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from core.api import image_url
from venues.models import Area, Sport

from .mailer import send_login_code
from .models import EmailOTP, PlayerSport, User, normalize_email

LEVEL_PCT = {0: 30, 1: 60, 2: 90}


def sport_payload(request, ps):
    return {
        "sport_id": ps.sport_id, "name": ps.sport.name, "level": ps.level,
        "level_label": ps.get_level_display(), "percent": LEVEL_PCT[ps.level],
        "image": image_url(request, ps.sport.image),
    }


def user_stats(user):
    from bookings.models import Booking
    done = Booking.objects.filter(user=user, status="completed")
    return {"games": done.count(), "hours": done.aggregate(h=Sum("duration"))["h"] or 0}


def me_payload(request, user):
    return {
        "id": user.id,
        "email": user.email,
        "masked_email": user.masked_email,
        "phone": user.phone,
        "masked_phone": user.masked_phone,
        "address": user.address,
        "profile_complete": bool(user.name and user.phone),
        "name": user.name,
        "handle": user.handle,
        "initials": user.initials,
        "avatar": image_url(request, user.avatar),
        "home_area": {"id": user.home_area_id, "name": user.home_area.name, "city": user.home_area.city.name}
        if user.home_area else None,
        "show_to_nearby": user.show_to_nearby,
        "notifications_on": user.notifications_on,
        "slot_alerts_on": user.slot_alerts_on,
        "referral_code": user.referral_code,
        "wallet_balance": user.wallet_balance,
        "sports": [sport_payload(request, ps) for ps in user.sports.select_related("sport")],
        "stats": user_stats(user),
        "is_staff": user.is_staff,
    }


def _clean_email(raw):
    email = normalize_email(raw)
    try:
        validate_email(email)
    except DjangoValidationError:
        raise ValidationError({"email": "Enter a valid email address."})
    return email


@api_view(["POST"])
def otp_request(request):
    email = _clean_email(request.data.get("email"))
    if EmailOTP.recently_sent(email):
        raise ValidationError({"email": "A code was just sent. Please wait 30 seconds before asking again."})
    code = EmailOTP.issue(email, dev_mode=settings.OTP_DEV_MODE)
    try:
        send_login_code(email, code)
    except Exception:
        if not settings.OTP_DEV_MODE:
            raise ValidationError({"email": "We couldn't send the email right now. Please try again."})
    data = {"email": email, "sent": True}
    if settings.OTP_DEV_MODE:
        data["dev_code"] = code
    return Response(data)


@api_view(["POST"])
def otp_verify(request):
    email = _clean_email(request.data.get("email"))
    code = str(request.data.get("code", "")).strip()
    otp = EmailOTP.objects.filter(email=email, used=False).first()
    if not otp or otp.is_expired():
        raise ValidationError({"code": "Code expired. Request a new one."})
    if otp.attempts >= EmailOTP.MAX_ATTEMPTS:
        raise ValidationError({"code": "Too many attempts. Request a new code."})
    if EmailOTP.hash(code) != otp.code_hash:
        otp.attempts += 1
        otp.save(update_fields=["attempts"])
        raise ValidationError({"code": "That code is incorrect."})
    otp.used = True
    otp.save(update_fields=["used"])
    user, created = User.objects.get_or_create(email=email)
    if not user.is_active:
        raise ValidationError({"email": "This account is disabled. Contact support."})
    from community.services import claim_invites
    claim_invites(user)  # groups they were invited to by email before signing up
    ref = (request.data.get("referral_code") or "").strip().upper()
    if created and ref:
        user.referred_by = User.objects.filter(referral_code=ref).first()
        user.save(update_fields=["referred_by"])
    refresh = RefreshToken.for_user(user)
    return Response({
        "access": str(refresh.access_token),
        "refresh": str(refresh),
        "is_new": created or not (user.name and user.phone),
        "user": me_payload(request, user),
    })


class MeSerializer(serializers.ModelSerializer):
    def validate_name(self, v):
        v = v.strip()
        if len(v) < 2:
            raise serializers.ValidationError("Please enter your name.")
        return v

    def validate_phone(self, v):
        v = v.strip()
        if not v:
            raise serializers.ValidationError("Please enter your mobile number.")
        digits = "".join(c for c in v if c.isdigit())
        if len(digits) == 10:
            digits = "91" + digits
        if not 11 <= len(digits) <= 15:
            raise serializers.ValidationError("Enter a valid mobile number.")
        return "+" + digits

    def validate_address(self, v):
        return v.strip()

    home_area_id = serializers.PrimaryKeyRelatedField(source="home_area", queryset=Area.objects.all(),
                                                      required=False, allow_null=True)

    class Meta:
        model = User
        fields = ["name", "phone", "address", "handle", "home_area_id", "show_to_nearby", "notifications_on",
                  "slot_alerts_on", "lat", "lng", "avatar"]


@api_view(["GET", "PATCH"])
@permission_classes([permissions.IsAuthenticated])
@parser_classes([JSONParser, MultiPartParser, FormParser])
def me(request):
    if request.method == "PATCH":
        s = MeSerializer(request.user, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
    return Response(me_payload(request, request.user))


@api_view(["PUT"])
@permission_classes([permissions.IsAuthenticated])
def my_sports(request):
    """Body: [{"sport_id": 1, "level": 2}, ...] – replaces the user's sports."""
    items = request.data if isinstance(request.data, list) else request.data.get("sports", [])
    keep = []
    for it in items:
        sport = Sport.objects.filter(pk=it.get("sport_id")).first()
        if not sport:
            continue
        level = max(0, min(2, int(it.get("level", 0))))
        PlayerSport.objects.update_or_create(user=request.user, sport=sport, defaults={"level": level})
        keep.append(sport.id)
    request.user.sports.exclude(sport_id__in=keep).delete()
    return Response(me_payload(request, request.user))
