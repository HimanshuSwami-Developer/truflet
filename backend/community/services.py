"""Match rules. API views stay thin and call these.

Lifecycle of a lobby
- Host pays upfront (Host covers all, or Split + Book & recover): `draft` → host pays the slot hold → `locked`.
- Split + Crowdfund first: `crowdfunding` (the turf calendar is NOT blocked) → pool reaches the turf price →
  the slot is booked from the pool → `locked`.
- `locked` → match ends → `completed`. Any state can end in `cancelled` / `expired`.

Timers (15-min payment window, slot conflicts, unfilled alerts, payout release) are applied lazily by
`sync()` whenever lobbies are read, so no background worker is needed.
"""
from datetime import date as date_cls, timedelta

from django.core.exceptions import ObjectDoesNotExist
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email
from django.db import transaction
from django.db.models import Count, F, Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from accounts.models import User, normalize_email, normalize_phone
from core.models import AppConfig, SupportTicket, notify

from .models import JoinRequest, Lobby, LobbyMember, LobbyMessage

PAY_WINDOW = timedelta(minutes=15)       # approved solo players must pay within this
UNFILLED_ALERT_MINUTES = 60              # crowdfunding lobby not full this close to kickoff → alert host
LATE_DROP_MINUTES = 30                   # leaving later than this is non-refundable
GEOFENCE_METRES = 150
CHECKIN_WINDOW = timedelta(minutes=15)   # GPS check-in: kickoff ± 15 min
RELEASE_AFTER = timedelta(minutes=15)    # silent payout release: match end + 15 min
PRIME_HOURS = range(18, 22)              # 6 PM – 10 PM: Book & recover is recommended
LIVE = ("draft", "crowdfunding", "locked")


def first_name(user):
    return (user.name or user.email.split("@")[0]).split(" ")[0]


def when(lobby):
    from bookings.services import fmt_hour
    return f"{lobby.date:%a, %-d %b} · {fmt_hour(lobby.start_hour)}"


def split_fee():
    return AppConfig.get().split_fee


def post(lobby, body, *, sender=None, kind="system", request=None, member=None):
    return LobbyMessage.objects.create(lobby=lobby, request=request, sender=sender, kind=kind,
                                       body=body[:500], member=member)


def _related_lobby(booking):
    try:
        return booking.lobby
    except ObjectDoesNotExist:
        return None


# ------------------------------------------------------------------ players

def parse_contact(raw):
    """Email, Indian mobile or referral code → normalised contact. Raises ValidationError."""
    raw = (raw or "").strip()
    code = raw.upper().replace(" ", "")
    phone_like = bool(raw) and all(ch.isdigit() or ch in "+-() " for ch in raw)
    if raw and not phone_like and "@" not in raw:
        if not code.startswith("PLAY-") and len(code) == 4:
            code = f"PLAY-{code}"  # "7KQ2" typed without the prefix
        return f"ref:{code}"
    if "@" in raw:
        email = normalize_email(raw)
        try:
            validate_email(email)
        except DjangoValidationError:
            raise ValidationError({"contact": "Enter a valid email address or 10-digit mobile number."})
        return email
    digits = "".join(ch for ch in raw if ch.isdigit())
    if len(digits) not in (10, 12):
        raise ValidationError({"contact": "Enter a mobile number, referral code or email."})
    return normalize_phone(digits)


def lookup_player(raw, me):
    """A Turflet player by email, mobile or referral code — the 'Known' friend picker."""
    contact = parse_contact(raw)
    qs = User.objects.filter(is_active=True)
    if contact.startswith("ref:"):
        user = qs.filter(referral_code=contact[4:]).first()
    elif "@" in contact:
        user = qs.filter(email=contact).first()
    else:
        user = qs.filter(phone=contact).first()
    if not user:
        raise ValidationError({"contact": "No Turflet player found. Add them as a guest instead."})
    if user.pk == me.pk:
        raise ValidationError({"contact": "That's you — you're already the host."})
    return user


def recent_players(me, limit=12):
    """People I've played matches with, most recent first."""
    lobby_ids = LobbyMember.objects.filter(user=me).values("lobby_id")
    seen, out = set(), []
    for m in (LobbyMember.objects.filter(lobby_id__in=lobby_ids, user__isnull=False, status="confirmed")
              .exclude(user=me).select_related("user").order_by("-created_at")[:100]):
        if m.user_id not in seen:
            seen.add(m.user_id)
            out.append(m.user)
        if len(out) >= limit:
            break
    return out


def host_stats(user):
    hosted = Lobby.objects.filter(host=user)
    done = hosted.filter(status="completed").count()
    flaked = hosted.filter(status="cancelled", cancelled_by="host").count()
    total = done + flaked
    return {"hosted": done, "reliability": round(100 * done / total) if total else None}


def attendance(user):
    from bookings.models import Booking
    played = (Booking.objects.filter(user=user, status="completed").count()
              + LobbyMember.objects.filter(user=user, status="confirmed", lobby__status="completed")
              .exclude(tag="host").count())
    drops = LobbyMember.objects.filter(user=user, tag="solo", status__in=("left", "removed")).count()
    total = played + drops
    return {"played": played, "drop_offs": drops, "score": round(100 * played / total) if total else None}


# ------------------------------------------------------------------ money helpers

def _charge(user, amount, method, upi_id, reference):
    from bookings.models import Booking
    from bookings.payments import get_provider
    if method not in dict(Booking.METHODS) or method in ("venue", "pool"):
        raise ValidationError({"method": "Unknown payment method."})
    if method == "wallet" and user.wallet_balance < amount:
        raise ValidationError({"method": "Not enough Turflet balance."})
    if method == "upi" and upi_id and "@" not in upi_id:
        raise ValidationError({"method": "Enter a valid UPI ID, e.g. yourname@bank"})
    result = get_provider().charge_amount(amount, method, reference)
    if not result.success:
        raise ValidationError({"payment": result.message or "Payment failed. Please try again."})
    if method == "wallet":
        User.objects.filter(pk=user.pk).update(wallet_balance=F("wallet_balance") - amount)
    return result.transaction_id


def _refund(member, why):
    """Returns everything this member paid. Claws back from the host if it was already released."""
    from bookings.payments import get_provider
    amount = member.amount_paid
    if amount <= 0 or member.escrow in ("refunded", "none"):
        member.refund_due = False
        member.save(update_fields=["refund_due", "updated_at"])
        return 0
    lobby = member.lobby
    if member.escrow == "released":
        User.objects.filter(pk=lobby.host_id, wallet_balance__gte=member.share_paid).update(
            wallet_balance=F("wallet_balance") - member.share_paid)
    get_provider().refund_amount(amount, member.transaction_id)
    if member.payment_method == "wallet" and member.user_id:
        User.objects.filter(pk=member.user_id).update(wallet_balance=F("wallet_balance") + amount)
    member.escrow, member.refund_due = "refunded", False
    if member.status in ("confirmed", "pending", "left"):
        member.status = "refunded"
    member.save(update_fields=["escrow", "refund_due", "status", "updated_at"])
    if member.user_id:
        notify(member.user, f"₹{amount} refunded", f"{lobby.venue.name} · {when(lobby)} · {why}", "match")
    return amount


def _pay_card(lobby, member):
    deadline = " · pay within 15 min" if member.pay_by else ""
    return post(lobby, f"₹{member.amount_due} due from {member.display_name}{deadline}", kind="payment", member=member)


# ------------------------------------------------------------------ creating

def _int(data, key, error):
    try:
        return int(data.get(key))
    except (TypeError, ValueError):
        raise ValidationError({key: error})


@transaction.atomic
def create_lobby(user, data):
    """Squad Builder. Returns (lobby, booking). `booking` is a held slot the host must pay now, or None
    for a crowdfunding lobby."""
    from bookings.services import check_range, create_hold, price_breakdown, resolve
    from venues.models import Venue
    venue = Venue.objects.filter(pk=data.get("venue"), is_active=True).first()
    if not venue:
        raise ValidationError({"venue": "Venue not found."})
    try:
        day = date_cls.fromisoformat(str(data.get("date", "")))
    except ValueError:
        raise ValidationError({"date": "Pick a date."})
    if day < timezone.localdate():
        raise ValidationError({"date": "Pick today or a future date."})
    start = _int(data, "start_hour", "Pick a start time.")
    duration = _int(data, "duration", "Pick a duration.")
    capacity = _int(data, "capacity", "Set the total number of players.")
    vs, court = resolve(venue, data.get("court"), data.get("sport"))

    rule = data.get("payment_rule") if data.get("payment_rule") in dict(Lobby.RULES) else "split"
    mode = data.get("booking_mode") if data.get("booking_mode") in dict(Lobby.MODES) else "book_recover"
    if rule == "host":
        mode = "book_recover"  # the host pays the slot now
    is_public = bool(data.get("is_public"))

    if capacity < 2 or capacity > vs.max_players:
        raise ValidationError({"capacity": f"Pick between 2 and {vs.max_players} players for {vs.sport.name}."})

    known, guests, seen = [], [], set()
    for f in data.get("friends") or []:
        if f.get("tag") == "guest":
            name = (f.get("name") or "").strip()
            if not name:
                raise ValidationError({"friends": "Give each guest a name."})
            guests.append(name[:60])
            continue
        friend = (User.objects.filter(pk=f["user_id"], is_active=True).first() if f.get("user_id")
                  else lookup_player(f.get("contact"), user))
        if not friend:
            raise ValidationError({"friends": "One of your friends couldn't be found."})
        if friend.pk == user.pk or friend.pk in seen:
            continue
        seen.add(friend.pk)
        known.append(friend)
    squad = 1 + len(known) + len(guests)
    if squad > capacity:
        raise ValidationError({"capacity": f"You've added {squad} players — raise the capacity to at least {squad}."})
    if not is_public and squad < capacity:
        # private full squad: players the host didn't name are the host's guests (covered by the host)
        guests += [f"Guest {len(guests) + i + 1}" for i in range(capacity - squad)]

    err = check_range(vs, court, day, start, duration)
    if err:
        raise ValidationError({"slot": err})
    turf_price = price_breakdown(vs, start, duration)["slot_amount"]
    upfront = rule == "host" or mode == "book_recover"
    lobby = Lobby.objects.create(
        host=user, venue=venue, court=court, sport=vs.sport, date=day, start_hour=start, duration=duration,
        capacity=capacity, payment_rule=rule, booking_mode=mode, is_public=is_public, turf_price=turf_price,
        status="draft" if upfront else "crowdfunding")
    booking = None
    fee = split_fee() if rule == "split" else 0
    share = lobby.share if rule == "split" else 0
    if upfront:
        booking = create_hold(user, venue, court.pk, vs.sport_id, day, start, duration)
        lobby.booking = booking
        lobby.save(update_fields=["booking"])
        host = LobbyMember.objects.create(lobby=lobby, user=user, tag="host", status="pending", share_due=booking.total)
    else:
        # crowdfund: the host pays their own share plus their guests' shares into the pool
        host = LobbyMember.objects.create(lobby=lobby, user=user, tag="host", status="pending",
                                          share_due=share * (1 + len(guests)), fee_due=fee)
    for friend in known:
        LobbyMember.objects.create(lobby=lobby, user=friend, tag="known",
                                   status="pending" if rule == "split" else "confirmed",
                                   share_due=share, fee_due=fee)
    for name in guests:
        LobbyMember.objects.create(lobby=lobby, guest_name=name, tag="guest", status="confirmed")

    post(lobby, f"{first_name(user)} created this match · {lobby.get_payment_rule_display()}"
                + (f" · {lobby.get_booking_mode_display()}" if rule == "split" else ""))
    if not upfront:
        post(lobby, "Crowdfunding: the turf is booked as soon as the pool covers the slot. "
                    "Money stays in escrow until then.")
        _pay_card(lobby, host)
        _invite_known(lobby)
    return lobby, booking


def _invite_known(lobby):
    for m in lobby.members.filter(tag="known").select_related("user"):
        if m.status == "pending":
            _pay_card(lobby, m)
        notify(m.user, f"{first_name(lobby.host)} added you to a match",
               f"{lobby.sport.name} at {lobby.venue.name} · {when(lobby)}", "match")


# ------------------------------------------------------------------ booking hooks

def on_booking_paid(booking):
    """The host paid the held slot: the turf is locked."""
    lobby = _related_lobby(booking)
    if not lobby or lobby.status != "draft":
        return
    with transaction.atomic():
        host = lobby.members.get(tag="host")
        host.status, host.share_paid, host.paid_at = "confirmed", booking.total, timezone.now()
        host.payment_method, host.transaction_id = booking.payment_method, booking.transaction_id
        host.save()
        lobby.status = "locked"
        lobby.save(update_fields=["status", "updated_at"])
        post(lobby, f"Turf locked · booking {booking.code}. "
                    + ("Shares are collected into escrow and released to the host at check-in."
                       if lobby.is_split else "The host covered the full amount — everyone plays free."))
        _invite_known(lobby)


def on_booking_cancelled(booking, by_venue=False):
    lobby = _related_lobby(booking)
    if lobby and lobby.is_live:
        _end(lobby, "cancelled", "venue" if by_venue else "host",
             "The venue cancelled this slot" if by_venue else "The host cancelled the match")


def on_venue_checkin(booking):
    """Tier 1: the turf manager scanned the booking QR / entered the PIN."""
    lobby = _related_lobby(booking)
    if lobby:
        release_payout(lobby, "qr")


def _end(lobby, status, by, why):
    """Cancel / expire a lobby and refund every payer in full."""
    for m in lobby.members.exclude(escrow__in=("none", "refunded")).select_related("user"):
        if m.tag == "host" and lobby.booking_id and m.escrow == "none":
            continue  # the host's slot payment is refunded by the booking's own cancellation
        _refund(m, why)
    lobby.requests.filter(status="pending").update(status="declined", decided_at=timezone.now())
    lobby.status, lobby.cancelled_by, lobby.alert = status, by, ""
    if lobby.payout_status in ("held", "disputed"):
        lobby.payout_status = "refunded"
    lobby.save(update_fields=["status", "cancelled_by", "alert", "payout_status", "updated_at"])
    post(lobby, f"{why}. Everyone who paid gets a full refund.")
    for m in lobby.active_members().exclude(user=None).exclude(tag="host").select_related("user"):
        notify(m.user, "Match cancelled", f"{lobby.venue.name} · {when(lobby)} · {why}", "match")


# ------------------------------------------------------------------ timers

def sync(lobbies):
    """Applies every time-based rule to these lobbies. Safe to call on every read."""
    for lobby in lobbies:
        if lobby.is_live or lobby.payout_status == "held":
            sync_one(lobby)


@transaction.atomic
def sync_one(lobby):
    from bookings.models import Booking
    now = timezone.now()
    # 15-minute payment window
    for m in lobby.members.filter(status="pending", pay_by__lt=now).select_related("user"):
        m.status = "removed"
        m.save(update_fields=["status", "updated_at"])
        post(lobby, f"{m.display_name} didn't pay within 15 minutes — the spot is open again.")
        if m.user_id:
            notify(m.user, "Payment window expired", f"Your spot at {lobby.venue.name} was released.", "match")
    if lobby.booking_id:
        Booking.sync_statuses(Booking.objects.filter(pk=lobby.booking_id))
        lobby.booking.refresh_from_db()

    if lobby.status == "draft":
        b = lobby.booking
        if b is None or b.status in ("expired", "cancelled"):
            lobby.status, lobby.cancelled_by = "expired", "system"
            lobby.save(update_fields=["status", "cancelled_by", "updated_at"])
        return

    if lobby.status == "crowdfunding":
        if now >= lobby.start_dt:
            _end(lobby, "expired", "system", "The pool didn't cover the slot before kickoff")
            return
        if not _slot_free(lobby):
            if lobby.alert != "slot_taken":
                lobby.alert = "slot_taken"
                lobby.save(update_fields=["alert", "updated_at"])
                post(lobby, "Another group booked this slot first. Host: switch to another slot or cancel "
                            "(everyone is refunded).")
                notify(lobby.host, "Your slot was booked by another group",
                       f"{lobby.venue.name} · {when(lobby)} — switch slot or cancel", "match")
        elif lobby.minutes_left <= UNFILLED_ALERT_MINUTES and lobby.alert == "":
            lobby.alert = "unfilled"
            lobby.save(update_fields=["alert", "updated_at"])
            post(lobby, "Kickoff is less than an hour away and the pool isn't full. Host: pay the remaining "
                        "balance, switch slot, or unpublish.")
            notify(lobby.host, "Your lobby isn't full yet",
                   f"{lobby.venue.name} · {when(lobby)} — pay the balance, switch slot or unpublish", "match")
        return

    if lobby.status == "completed":
        # an admin put a disputed payout back on hold after review → pay it out
        if lobby.payout_status == "held" and now >= lobby.end_dt + RELEASE_AFTER:
            release_payout(lobby, "auto")
        return

    if lobby.status == "locked":
        b = lobby.booking
        if b is not None and b.status == "cancelled":
            _end(lobby, "cancelled", "host", "The booking was cancelled")
            return
        if lobby.payout_status == "held" and now >= lobby.end_dt + RELEASE_AFTER:
            release_payout(lobby, "auto")
        if now >= lobby.end_dt + RELEASE_AFTER or (now >= lobby.end_dt and lobby.payout_status != "held"):
            lobby.status = "completed"
            lobby.save(update_fields=["status", "updated_at"])


def _slot_free(lobby, date=None, start=None, court=None):
    from bookings.services import check_range
    from venues.models import VenueSport
    vs = VenueSport.objects.select_related("venue").get(venue=lobby.venue, sport=lobby.sport)
    return check_range(vs, court or lobby.court, date or lobby.date, start if start is not None else lobby.start_hour,
                       lobby.duration, exclude_booking=lobby.booking) is None


# ------------------------------------------------------------------ joining

def _locked(lobby):
    return Lobby.objects.select_for_update().select_related("venue", "court", "sport", "host", "booking").get(pk=lobby.pk)


def membership(lobby, user):
    if not user.is_authenticated:
        return None
    return lobby.members.filter(user=user).first()


def can_enter_room(lobby, user):
    m = membership(lobby, user)
    return bool(m and m.status in ("pending", "confirmed"))


@transaction.atomic
def request_join(lobby, user, note=""):
    sync_one(lobby)
    lobby = _locked(lobby)
    if not lobby.is_public or lobby.status not in ("crowdfunding", "locked"):
        raise ValidationError({"lobby": "This lobby isn't taking requests."})
    if lobby.start_dt <= timezone.now():
        raise ValidationError({"lobby": "This match has already started."})
    if lobby.host_id == user.pk:
        raise ValidationError({"lobby": "You're hosting this match."})
    if can_enter_room(lobby, user):
        raise ValidationError({"lobby": "You're already in this match."})
    if lobby.spots_left <= 0:
        raise ValidationError({"lobby": "This lobby is full."})
    req, created = JoinRequest.objects.get_or_create(lobby=lobby, user=user)
    if not created:
        if req.status == "pending":
            return req
        if req.status == "declined":
            raise ValidationError({"lobby": "The host declined your request for this match."})
        req.status, req.decided_at = "pending", None
        req.save(update_fields=["status", "decided_at", "updated_at"])
    stats = attendance(user)
    score = f"{stats['score']}% attendance" if stats["score"] is not None else "new player"
    post(lobby, f"{first_name(user)} asked to join · {stats['played']} games played · {score}", request=req)
    note = (note or "").strip()
    if note:
        post(lobby, note, sender=user, kind="text", request=req)
    notify(lobby.host, f"{first_name(user)} wants to join your match",
           f"{lobby.venue.name} · {when(lobby)} · review in Requests", "match")
    return req


@transaction.atomic
def withdraw(req, user):
    if req.user_id != user.pk or req.status != "pending":
        raise ValidationError({"request": "Nothing to withdraw."})
    req.status, req.decided_at = "withdrawn", timezone.now()
    req.save(update_fields=["status", "decided_at", "updated_at"])
    post(req.lobby, f"{first_name(user)} withdrew the request.", request=req)


@transaction.atomic
def decide(req, host, approve):
    lobby = _locked(req.lobby)
    if lobby.host_id != host.pk:
        raise ValidationError({"request": "Only the host can review requests."})
    req = JoinRequest.objects.select_for_update().select_related("user").get(pk=req.pk)
    if req.status != "pending":
        raise ValidationError({"request": "This request was already handled."})
    now = timezone.now()
    if not approve:
        req.status, req.decided_at = "declined", now
        req.save(update_fields=["status", "decided_at", "updated_at"])
        post(lobby, "The host declined this request. Thread closed.", request=req)
        notify(req.user, "Request declined", f"{lobby.venue.name} · {when(lobby)}", "match")
        return req, None
    sync_one(lobby)
    if lobby.spots_left <= 0:
        raise ValidationError({"request": "The lobby is full — no spot left to approve."})
    member, _ = LobbyMember.objects.get_or_create(lobby=lobby, user=req.user, defaults={"tag": "solo"})
    member.tag, member.refund_due, member.checked_in_at = "solo", False, None
    member.share_paid = member.fee_paid = 0
    member.escrow, member.paid_at, member.payment_method, member.transaction_id = "none", None, "", ""
    if lobby.is_split:
        member.status, member.share_due, member.fee_due, member.pay_by = "pending", lobby.share, split_fee(), now + PAY_WINDOW
    else:
        member.status, member.share_due, member.fee_due, member.pay_by = "confirmed", 0, 0, None
    member.save()
    req.status, req.decided_at = "approved", now
    req.save(update_fields=["status", "decided_at", "updated_at"])
    post(lobby, "Approved — you're in the Match Room now.", request=req)
    post(lobby, f"{first_name(req.user)} joined the match (solo)")
    if lobby.is_split:
        _pay_card(lobby, member)
        body = f"Pay your ₹{member.amount_due} share within 15 minutes to keep your spot."
    else:
        body = "The host is covering the slot — you're confirmed at ₹0."
    notify(req.user, "You're approved!", f"{lobby.venue.name} · {when(lobby)} · {body}", "match")
    return req, member


# ------------------------------------------------------------------ chat

def check_thread(req, user):
    if user.pk not in (req.user_id, req.lobby.host_id):
        raise ValidationError({"request": "This thread is private."})


def send(lobby, user, body, req=None):
    body = (body or "").strip()
    if not body:
        raise ValidationError({"body": "Type a message."})
    if req is not None:
        check_thread(req, user)
        if req.status != "pending":
            raise ValidationError({"body": "This thread is closed."})
    elif not can_enter_room(lobby, user):
        raise ValidationError({"body": "Only players in this match can chat here."})
    return post(lobby, body, sender=user, kind="text", request=req)


# ------------------------------------------------------------------ paying

def checkout(lobby, user):
    m = membership(lobby, user)
    if not m or m.status != "pending" or lobby.status not in ("crowdfunding", "locked"):
        raise ValidationError({"payment": "Nothing to pay for this match."})
    guests = lobby.members.filter(tag="guest", status="confirmed").count() if m.tag == "host" else 0
    return {
        "member_id": m.pk,
        "turf_share": lobby.share,
        "guest_shares": lobby.share * guests,
        "guests": guests,
        "platform_fee": m.fee_due,
        "total": m.amount_due,
        "pay_by": m.pay_by.isoformat() if m.pay_by else None,
        "escrow_note": ("Your money goes to Turflet's escrow, never to the host. It's paid to the venue once the "
                        "pool covers the slot, and refunded in full if the turf isn't booked."
                        if lobby.status == "crowdfunding" else
                        "Your money goes to Turflet's escrow, never to the host. The host receives it only after "
                        "the venue confirms your group arrived — report a no-show and it stays on hold."),
    }


@transaction.atomic
def pay_share(lobby, user, method, upi_id=""):
    lobby = _locked(lobby)
    sync_one(lobby)
    m = LobbyMember.objects.select_for_update().filter(lobby=lobby, user=user).first()
    if not m or m.status != "pending":
        raise ValidationError({"payment": "Your payment window has closed — ask the host to approve you again."
                                          if m and m.status == "removed" else "Nothing to pay for this match."})
    if lobby.status not in ("crowdfunding", "locked"):
        raise ValidationError({"payment": "This match isn't collecting payments."})
    amount = m.amount_due
    txn = _charge(user, amount, method, upi_id, f"LB-{lobby.pk}-{m.pk}")
    m.share_paid, m.fee_paid = m.share_due, m.fee_due
    m.status, m.escrow, m.pay_by, m.paid_at = "confirmed", "held", None, timezone.now()
    m.payment_method, m.transaction_id = method, txn
    m.save()
    post(lobby, f"{m.display_name} paid ₹{amount} into escrow ✓")
    if m.tag != "host":
        notify(lobby.host, f"{first_name(user)} paid their share", f"{lobby.venue.name} · {when(lobby)}", "match")
    # a replacement joined → refund the earliest early drop-off
    if m.tag in ("solo", "known"):
        leaver = lobby.members.filter(refund_due=True).order_by("updated_at").first()
        if leaver:
            _refund(leaver, "A replacement joined")
            post(lobby, f"{leaver.display_name}'s spot was filled — their share is refunded.")
    if lobby.status == "locked" and lobby.booking_mode == "book_recover" and lobby.payout_status == "none":
        lobby.payout_status = "held"
        lobby.save(update_fields=["payout_status", "updated_at"])
    if lobby.status == "crowdfunding" and lobby.pooled() >= lobby.turf_price:
        _lock_from_pool(lobby)
    elif lobby.status == "locked" and lobby.payout_status == "settled" and m.tag != "host":
        # the pool already paid the venue; this share recovers the host's balance payment
        lobby.payout_status = "held"
        lobby.save(update_fields=["payout_status", "updated_at"])
    return m


def _lock_from_pool(lobby):
    """Crowdfund target reached: book the slot and settle the pool to the venue."""
    from bookings.models import Booking
    from venues.models import Court
    Court.objects.select_for_update().filter(pk=lobby.court_id).first()
    if not _slot_free(lobby):
        lobby.alert = "slot_taken"
        lobby.save(update_fields=["alert", "updated_at"])
        post(lobby, "The pool is full, but another group booked this slot first. Host: switch slot or cancel.")
        notify(lobby.host, "Your slot was booked by another group", f"{lobby.venue.name} · {when(lobby)}", "match")
        return False
    hours = range(lobby.start_hour, lobby.end_hour)
    booking = Booking.objects.create(
        user=lobby.host, venue=lobby.venue, court=lobby.court, sport=lobby.sport, date=lobby.date,
        start_hour=lobby.start_hour, duration=lobby.duration, players=lobby.capacity,
        slot_amount=lobby.turf_price, peak_hours=sum(1 for h in hours if lobby.venue.is_peak(h)),
        total=lobby.turf_price, status="confirmed", payment_status="paid", payment_method="pool",
        transaction_id=f"POOL-{lobby.pk}", paid_at=timezone.now())
    lobby.members.filter(escrow="held").update(escrow="settled")
    lobby.booking, lobby.status, lobby.alert, lobby.payout_status = booking, "locked", "", "settled"
    lobby.payout_trigger, lobby.payout_at = "venue", timezone.now()
    lobby.save()
    post(lobby, f"Turf locked! The pool covered ₹{lobby.turf_price} and was paid to the venue · booking {booking.code}")
    for m in lobby.active_members().exclude(user=None).select_related("user"):
        notify(m.user, "Turf locked 🎉", f"{lobby.venue.name} · {when(lobby)}", "match")
    return True


@transaction.atomic
def pay_balance(lobby, host, method, upi_id=""):
    """Crowdfund alert option: the host pays whatever the pool is missing and the slot is booked now."""
    lobby = _locked(lobby)
    if lobby.host_id != host.pk or lobby.status != "crowdfunding":
        raise ValidationError({"lobby": "Only the host of a crowdfunding lobby can pay the balance."})
    if not _slot_free(lobby):
        raise ValidationError({"lobby": "This slot was booked by another group — switch to another slot."})
    balance = max(0, lobby.turf_price - lobby.pooled())
    h = lobby.members.select_for_update().get(tag="host")
    if balance:
        txn = _charge(host, balance, method, upi_id, f"LB-{lobby.pk}-balance")
        h.share_paid += balance
        h.payment_method, h.transaction_id = method, txn
    h.status, h.escrow, h.paid_at, h.pay_by = "confirmed", "held", timezone.now(), None
    h.share_due, h.fee_due = h.share_paid, h.fee_paid
    h.save()
    post(lobby, f"{first_name(host)} paid the remaining ₹{balance}.")
    lobby.booking_mode = "book_recover"  # players who still pay now recover the host's money
    lobby.save(update_fields=["booking_mode", "updated_at"])
    _lock_from_pool(lobby)
    return lobby


# ------------------------------------------------------------------ host controls

def _host(lobby, user):
    if lobby.host_id != user.pk:
        raise ValidationError({"lobby": "Only the host can do that."})


@transaction.atomic
def switch_slot(lobby, host, data):
    from bookings.services import price_breakdown, resolve
    lobby = _locked(lobby)
    _host(lobby, host)
    if lobby.status != "crowdfunding":
        raise ValidationError({"lobby": "Only an unbooked (crowdfunding) lobby can switch slots."})
    try:
        day = date_cls.fromisoformat(str(data.get("date", "")))
    except ValueError:
        raise ValidationError({"date": "Pick a date."})
    start = _int(data, "start_hour", "Pick a start time.")
    vs, court = resolve(lobby.venue, data.get("court") or lobby.court_id, lobby.sport_id)
    if day < timezone.localdate():
        raise ValidationError({"date": "Pick today or a future date."})
    if not _slot_free(lobby, date=day, start=start, court=court):
        raise ValidationError({"slot": "That slot isn't available. Pick another one."})
    lobby.date, lobby.start_hour, lobby.court, lobby.alert = day, start, court, ""
    lobby.turf_price = price_breakdown(vs, start, lobby.duration)["slot_amount"]
    lobby.save()
    for m in lobby.members.filter(status="pending").exclude(tag="host"):
        m.share_due = lobby.share
        m.save(update_fields=["share_due", "updated_at"])
    post(lobby, f"The host moved the match to {when(lobby)} · {court.name}.")
    for m in lobby.active_members().exclude(user=None).exclude(tag="host").select_related("user"):
        notify(m.user, "Match moved", f"{lobby.venue.name} · {when(lobby)}", "match")
    if lobby.pooled() >= lobby.turf_price:
        _lock_from_pool(lobby)
    return lobby


@transaction.atomic
def unpublish(lobby, host):
    """Stop recruiting: refund paid solo players, close requests, keep the private squad chat."""
    lobby = _locked(lobby)
    _host(lobby, host)
    if not lobby.is_live:
        raise ValidationError({"lobby": "This match has ended."})
    for m in lobby.members.filter(tag="solo", status__in=("pending", "confirmed")):
        if m.amount_paid:
            _refund(m, "The host closed the lobby to solo players")
        m.status = "removed" if m.status == "pending" else "refunded"
        m.save(update_fields=["status", "updated_at"])
    for req in lobby.requests.filter(status="pending"):
        req.status, req.decided_at = "declined", timezone.now()
        req.save(update_fields=["status", "decided_at", "updated_at"])
        post(lobby, "The host stopped recruiting. Thread closed.", request=req)
    lobby.is_public = False
    if lobby.alert == "unfilled":
        lobby.alert = ""
    lobby.save(update_fields=["is_public", "alert", "updated_at"])
    post(lobby, "The host unpublished this lobby. Solo players were refunded; the squad chat stays.")
    return lobby


@transaction.atomic
def cancel_lobby(lobby, host, reason=""):
    from bookings import services as booking_services
    lobby = _locked(lobby)
    _host(lobby, host)
    if lobby.status == "draft":
        if lobby.booking_id:
            booking_services.cancel(lobby.booking, reason or "Match cancelled")
        lobby.status, lobby.cancelled_by = "cancelled", "host"
        lobby.save(update_fields=["status", "cancelled_by", "updated_at"])
    elif lobby.status == "crowdfunding":
        _end(lobby, "cancelled", "host", "The host cancelled the match")
    elif lobby.status == "locked":
        booking_services.cancel(lobby.booking, reason or "Match cancelled")  # → on_booking_cancelled
    else:
        raise ValidationError({"lobby": "This match has already ended."})
    lobby.refresh_from_db()
    return lobby


@transaction.atomic
def remove_member(lobby, host, member_id):
    lobby = _locked(lobby)
    _host(lobby, host)
    m = lobby.members.filter(pk=member_id).exclude(tag="host").first()
    if not m or m.status not in ("pending", "confirmed"):
        raise ValidationError({"member": "That player isn't in the match."})
    if m.amount_paid:
        _refund(m, "The host removed you from the match")
    m.status = "removed"
    m.save(update_fields=["status", "updated_at"])
    post(lobby, f"The host removed {m.display_name}.")
    return lobby


@transaction.atomic
def leave(lobby, user):
    lobby = _locked(lobby)
    m = LobbyMember.objects.select_for_update().filter(lobby=lobby, user=user).first()
    if not m or m.status not in ("pending", "confirmed"):
        raise ValidationError({"lobby": "You're not in this match."})
    if m.tag == "host":
        raise ValidationError({"lobby": "Hosts cancel the match instead of leaving."})
    if lobby.start_dt <= timezone.now():
        raise ValidationError({"lobby": "The match has started."})
    outcome = "no payment to refund"
    if m.amount_paid and lobby.status == "crowdfunding":
        _refund(m, "You left before the turf was booked")
        outcome = "refunded now (the turf wasn't booked yet)"
    elif m.amount_paid and lobby.minutes_left >= LATE_DROP_MINUTES:
        m.refund_due = True
        outcome = "refunded once a replacement joins or the slot is released"
    elif m.amount_paid:
        m.escrow = "forfeited"
        outcome = "not refundable (less than 30 minutes before kickoff)"
    m.status = "left" if m.status != "refunded" else m.status
    m.save()
    post(lobby, f"{m.display_name} left the match — a spot is open.")
    notify(lobby.host, f"{m.display_name} left your match", f"{lobby.venue.name} · {when(lobby)}", "match")
    return outcome


# ------------------------------------------------------------------ arrival & payout

@transaction.atomic
def checkin(lobby, user, lat, lng):
    """Tier 2: GPS geofence check-in near kickoff."""
    lobby = _locked(lobby)
    m = lobby.members.filter(user=user, status="confirmed").first()
    if not m:
        raise ValidationError({"checkin": "Only confirmed players can check in."})
    if lobby.status != "locked":
        raise ValidationError({"checkin": "The turf isn't booked yet."})
    now = timezone.now()
    if not (lobby.start_dt - CHECKIN_WINDOW <= now <= lobby.start_dt + CHECKIN_WINDOW):
        raise ValidationError({"checkin": "Check-in is open from 15 minutes before to 15 minutes after kickoff."})
    km = lobby.venue.distance_km(lat, lng)
    if km is None:
        raise ValidationError({"checkin": "We couldn't read your location."})
    if km * 1000 > GEOFENCE_METRES:
        raise ValidationError({"checkin": f"You're {int(km * 1000)} m from the venue — get within {GEOFENCE_METRES} m."})
    m.checked_in_at = now
    m.save(update_fields=["checked_in_at", "updated_at"])
    post(lobby, f"{m.display_name} checked in at the venue 📍")
    arrived = lobby.members.filter(checked_in_at__isnull=False)
    if arrived.filter(tag="host").exists() and arrived.filter(tag="solo").exists():
        release_payout(lobby, "gps")
    return m


def release_payout(lobby, trigger):
    """Pays the escrowed shares to the host (Book & recover)."""
    with transaction.atomic():
        lobby = Lobby.objects.select_for_update().get(pk=lobby.pk)
        if lobby.payout_status != "held":
            return 0
        held = list(lobby.members.filter(escrow="held").exclude(tag="host"))
        total = sum(m.share_paid for m in held)
        if total:
            User.objects.filter(pk=lobby.host_id).update(wallet_balance=F("wallet_balance") + total)
        LobbyMember.objects.filter(pk__in=[m.pk for m in held]).update(escrow="released", refund_due=False)
        lobby.payout_status, lobby.payout_trigger, lobby.payout_at = "released", trigger, timezone.now()
        lobby.save(update_fields=["payout_status", "payout_trigger", "payout_at", "updated_at"])
        how = {"qr": "the venue scanned your booking", "gps": "your group checked in at the venue",
               "auto": "no no-show was reported"}[trigger]
        post(lobby, f"₹{total} released from escrow to the host — {how}.")
        if total:
            notify(lobby.host, f"₹{total} added to your Turflet balance", f"Recovered shares · {how}", "match")
        return total


@transaction.atomic
def report_no_show(lobby, user, reason=""):
    m = lobby.members.filter(user=user, status="confirmed").exclude(tag="host").first()
    if not m:
        raise ValidationError({"report": "Only players in this match can report a no-show."})
    now = timezone.now()
    if not (lobby.start_dt <= now <= lobby.end_dt + RELEASE_AFTER):
        raise ValidationError({"report": "You can report a no-show during the match."})
    SupportTicket.objects.create(
        user=user, booking=lobby.booking, subject=f"No-show report · match #{lobby.pk}",
        message=(reason or "The host / turf didn't show up.")[:2000])
    held = lobby.payout_status == "held"
    if held:
        lobby.payout_status = "disputed"
        lobby.save(update_fields=["payout_status", "updated_at"])
    post(lobby, f"{m.display_name} reported a no-show. "
                + ("The payout is on hold until support reviews it." if held else "Support will review it."))
    notify(lobby.host, "A player reported a no-show", f"{lobby.venue.name} · {when(lobby)}", "match")
    return held


# ------------------------------------------------------------------ discovery

def upcoming_public(qs):
    """Public, recruiting lobbies that haven't started and still have spots."""
    now = timezone.localtime()
    qs = (qs.filter(is_public=True, status__in=("crowdfunding", "locked"))
          .filter(Q(date__gt=now.date()) | Q(date=now.date(), start_hour__gt=now.hour)))
    sync(list(qs))
    qs = qs.filter(status__in=("crowdfunding", "locked")).annotate(
        active=Count("members", filter=Q(members__status__in=("pending", "confirmed")))
    ).filter(active__lt=F("capacity"))
    return qs.select_related("venue__area", "court", "sport", "host").order_by("date", "start_hour")


def open_lobby_counts(venue_ids):
    """{venue_id: number of recruiting lobbies with spots}, without syncing (used on venue cards)."""
    now = timezone.localtime()
    rows = (Lobby.objects.filter(venue_id__in=venue_ids, is_public=True, status__in=("crowdfunding", "locked"))
            .filter(Q(date__gt=now.date()) | Q(date=now.date(), start_hour__gt=now.hour))
            .annotate(active=Count("members", filter=Q(members__status__in=("pending", "confirmed"))))
            .filter(active__lt=F("capacity")).values_list("venue_id", flat=True))
    counts = {}
    for vid in rows:
        counts[vid] = counts.get(vid, 0) + 1
    return counts


def lobby_hours(court, day):
    """{hour: {"lobbies": n, "spots": open spots}} for the slot matrix."""
    out = {}
    for lb in upcoming_public(Lobby.objects.filter(court=court, date=day)):
        spots = lb.capacity - lb.active
        for h in range(lb.start_hour, lb.end_hour):
            cell = out.setdefault(h, {"lobbies": 0, "spots": 0})
            cell["lobbies"] += 1
            cell["spots"] += spots
    return out
