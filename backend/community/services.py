"""Rules for groups and open games. API views stay thin and call these."""
from django.core.validators import validate_email
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import F, Q
from rest_framework.exceptions import ValidationError

from accounts.models import User, normalize_email, normalize_phone
from core.models import AppConfig, notify

from .models import GroupGame, GroupInvite, GroupMembership, OpenGame, OpenGamePlayer, PlayerGroup


def _first_name(user):
    return (user.name or user.email.split("@")[0]).split(" ")[0]


def _when(booking):
    from bookings.services import fmt_hour
    return f"{booking.date:%a, %-d %b} · {fmt_hour(booking.start_hour)}"


# ------------------------------------------------------------------ groups

def parse_contact(raw):
    """Email or Indian mobile → normalised contact string. Raises ValidationError."""
    raw = (raw or "").strip()
    if "@" in raw:
        email = normalize_email(raw)
        try:
            validate_email(email)
        except DjangoValidationError:
            raise ValidationError({"contact": "Enter a valid email address or 10-digit mobile number."})
        return email
    digits = "".join(ch for ch in raw if ch.isdigit())
    if len(digits) not in (10, 12):
        raise ValidationError({"contact": "Enter a valid email address or 10-digit mobile number."})
    return normalize_phone(digits)


def find_user(contact):
    if "@" in contact:
        return User.objects.filter(email=contact, is_active=True).first()
    return User.objects.filter(phone=contact, is_active=True).first()


def claim_invites(user):
    """Joins every group this player was invited to by email or phone before they signed up."""
    contacts = [user.email] + ([normalize_phone(user.phone)] if user.phone else [])
    for inv in GroupInvite.objects.filter(contact__in=contacts).select_related("group"):
        _, created = GroupMembership.objects.get_or_create(group=inv.group, user=user)
        if created:
            notify(user, f"You joined {inv.group.name}", "You were invited to this group on Turflet", "group")
        inv.delete()


def create_group(user, name):
    name = (name or "").strip()
    if len(name) < 2:
        raise ValidationError({"name": "Give the group a name."})
    group = PlayerGroup.objects.create(name=name[:60], created_by=user)
    GroupMembership.objects.create(group=group, user=user, role="admin")
    return group


def membership(group, user):
    m = GroupMembership.objects.filter(group=group, user=user).first()
    if not m:
        raise ValidationError({"group": "You are not in this group."})
    return m


@transaction.atomic
def add_member(group, by, raw_contact):
    """Adds an existing player straight away, otherwise stores an invite (and emails it).
    Returns ("added", user) or ("invited", contact)."""
    membership(group, by)
    contact = parse_contact(raw_contact)
    user = find_user(contact)
    if user:
        _, created = GroupMembership.objects.get_or_create(group=group, user=user)
        if not created:
            raise ValidationError({"contact": "Already in this group."})
        notify(user, f"Added to {group.name}", f"{_first_name(by)} added you to the group", "group")
        return "added", user
    GroupInvite.objects.get_or_create(group=group, contact=contact, defaults={"invited_by": by})
    if "@" in contact:
        _email_invite(contact, group, by)
    return "invited", contact


def _email_invite(email, group, by):
    from django.conf import settings
    from django.core.mail import send_mail
    try:
        send_mail(
            f"{_first_name(by)} invited you to {group.name} on Turflet",
            f"{_first_name(by)} added you to the group \"{group.name}\" on Turflet.\n\n"
            f"Sign in to the Turflet app with this email ({email}) and you'll be in the group automatically. "
            f"You can also join with the code {group.invite_code} (Profile → My groups → Join with code).",
            settings.DEFAULT_FROM_EMAIL, [email], fail_silently=True)
    except Exception:
        pass


def join_by_code(user, code):
    group = PlayerGroup.objects.filter(invite_code=(code or "").strip().upper()).first()
    if not group:
        raise ValidationError({"code": "No group with that code."})
    _, created = GroupMembership.objects.get_or_create(group=group, user=user)
    if created:
        for m in group.memberships.exclude(user=user).filter(role="admin").select_related("user"):
            notify(m.user, f"{_first_name(user)} joined {group.name}", "Joined with the invite code", "group")
    return group


@transaction.atomic
def leave_group(group, user):
    m = membership(group, user)
    m.delete()
    if not group.memberships.exists():
        group.delete()
        return
    if m.role == "admin" and not group.memberships.filter(role="admin").exists():
        # hand admin to the longest-standing member
        first = group.memberships.order_by("joined_at").first()
        first.role = "admin"
        first.save(update_fields=["role"])


def remove_member(group, by, user_id):
    if membership(group, by).role != "admin":
        raise ValidationError({"group": "Only group admins can remove members."})
    GroupMembership.objects.filter(group=group, user_id=user_id).exclude(user=by).delete()


# ------------------------------------------------------------------ booking hooks

def attach_to_hold(booking, user, group_id=None, open_players=None):
    """Called right after a slot hold is created: links it to a group or opens it to strangers."""
    if group_id:
        group = PlayerGroup.objects.filter(pk=group_id).first()
        if not group:
            raise ValidationError({"group": "Group not found."})
        membership(group, user)
        GroupGame.objects.create(booking=booking, group=group)
    elif open_players:
        try:
            n = int(open_players)
        except (TypeError, ValueError):
            raise ValidationError({"open_players": "Pick how many players in total."})
        if n < 2 or n > max(2, booking.players):
            raise ValidationError({"open_players": f"Pick between 2 and {booking.players} players."})
        OpenGame.objects.create(booking=booking, total_players=n)


def on_paid(booking):
    gg = getattr(booking, "group_game", None)
    if gg:
        host = _first_name(booking.user)
        for m in gg.group.memberships.exclude(user=booking.user).select_related("user"):
            notify(m.user, f"{host} booked a game for {gg.group.name}",
                   f"{booking.sport.name} at {booking.venue.name} · {_when(booking)}", "group")


def on_cancelled(booking):
    """Host cancelled: refund everyone who joined the open game and tell the group."""
    from bookings.payments import get_provider
    og = getattr(booking, "open_game", None)
    if og:
        for p in og.players.filter(status="joined").select_related("user"):
            get_provider().refund(booking, p.amount)
            p.status = "refunded"
            p.save(update_fields=["status", "updated_at"])
            User.objects.filter(pk=booking.user_id, wallet_balance__gte=p.amount).update(
                wallet_balance=F("wallet_balance") - p.amount)
            if p.payment_method == "wallet":
                User.objects.filter(pk=p.user_id).update(wallet_balance=F("wallet_balance") + p.amount)
            notify(p.user, "Open game cancelled",
                   f"{booking.venue.name} · {_when(booking)} · ₹{p.amount} refunded", "game")
    gg = getattr(booking, "group_game", None)
    if gg:
        for m in gg.group.memberships.exclude(user=booking.user).select_related("user"):
            notify(m.user, f"Game cancelled for {gg.group.name}", f"{booking.venue.name} · {_when(booking)}", "group")


# ------------------------------------------------------------------ open games

def open_games_at(venue):
    from django.utils import timezone

    from bookings.models import Booking
    Booking.sync_statuses(Booking.objects.filter(venue=venue))
    today = timezone.localdate()
    hour = timezone.localtime().hour
    qs = (OpenGame.objects.filter(booking__venue=venue, booking__status="confirmed")
          .filter(Q(booking__date__gt=today) | Q(booking__date=today, booking__start_hour__gt=hour))
          .select_related("booking__user", "booking__sport", "booking__court")
          .order_by("booking__date", "booking__start_hour"))
    return list(qs)


@transaction.atomic
def join_open_game(game, user, method, upi_id=""):
    from bookings.models import Booking
    from bookings.payments import get_provider
    game = OpenGame.objects.select_for_update().select_related("booking__user", "booking__venue").get(pk=game.pk)
    b = game.booking
    if b.status != "confirmed" or b.hours_left <= 0:
        raise ValidationError({"game": "This game is no longer open."})
    if b.user_id == user.id:
        raise ValidationError({"game": "You're hosting this game."})
    existing = game.players.filter(user=user).first()
    if existing and existing.status == "joined":
        raise ValidationError({"game": "You've already joined this game."})
    if game.spots_left <= 0:
        raise ValidationError({"game": "This game is full."})
    if method not in dict(Booking.METHODS) or method == "venue":
        raise ValidationError({"method": "Unknown payment method."})
    amount = game.share
    if method == "wallet" and user.wallet_balance < amount:
        raise ValidationError({"method": "Not enough Turflet balance."})
    if method == "upi" and upi_id and "@" not in upi_id:
        raise ValidationError({"method": "Enter a valid UPI ID, e.g. yourname@bank"})
    result = get_provider().charge_amount(amount, method, f"OG-{game.pk}-{user.pk}")
    if not result.success:
        raise ValidationError({"payment": result.message or "Payment failed. Please try again."})
    if method == "wallet":
        User.objects.filter(pk=user.pk).update(wallet_balance=F("wallet_balance") - amount)
    User.objects.filter(pk=b.user_id).update(wallet_balance=F("wallet_balance") + amount)
    if existing:
        existing.status, existing.amount = "joined", amount
        existing.payment_method, existing.transaction_id = method, result.transaction_id
        existing.save()
    else:
        OpenGamePlayer.objects.create(game=game, user=user, amount=amount, payment_method=method,
                                      transaction_id=result.transaction_id)
    notify(b.user, f"{_first_name(user)} joined your game",
           f"₹{amount} added to your Turflet balance · {game.spots_left} spot{'s' if game.spots_left != 1 else ''} left",
           "game")
    notify(user, "You're in!", f"{b.venue.name} · {_when(b)}", "game")
    return game


@transaction.atomic
def leave_open_game(game, user):
    from bookings.payments import get_provider
    p = OpenGamePlayer.objects.select_for_update().filter(game=game, user=user, status="joined").first()
    if not p:
        raise ValidationError({"game": "You haven't joined this game."})
    b = game.booking
    cutoff = AppConfig.get().free_cancel_hours
    if b.hours_left < cutoff:
        raise ValidationError({"game": f"You can leave up to {cutoff} hours before the game."})
    get_provider().refund(b, p.amount)
    p.status = "left"
    p.save(update_fields=["status", "updated_at"])
    User.objects.filter(pk=b.user_id, wallet_balance__gte=p.amount).update(wallet_balance=F("wallet_balance") - p.amount)
    if p.payment_method == "wallet":
        User.objects.filter(pk=user.pk).update(wallet_balance=F("wallet_balance") + p.amount)
    notify(b.user, f"{_first_name(user)} left your game", f"{b.venue.name} · {_when(b)}", "game")
    return p
