"""Matches API: lobbies, the solo request thread, the Match Room chat, split checkout and host controls."""
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from bookings.services import fmt_hour
from venues.models import Area, City, Venue

from . import services
from .models import JoinRequest, Lobby, LobbyMember, LobbyMessage

Auth = permissions.IsAuthenticated


def _initials(u):
    parts = [p for p in (u.name or "").split() if p]
    return "".join(p[0] for p in parts[:2]).upper() or u.email[:2].upper()


def person(u, me=None):
    return {"id": u.id, "name": u.name or u.email.split("@")[0], "initials": _initials(u),
            "is_me": bool(me and me.is_authenticated and me.id == u.id)}


def slot_state(lobby):
    """What the solo player sees on the card: is the turf already paid for?"""
    if lobby.status == "locked":
        return "turf_locked"
    if lobby.status in ("crowdfunding", "draft"):
        return "crowdfunding"
    return lobby.status


def lobby_card(lobby, me):
    members = list(lobby.members.select_related("user"))
    active = [m for m in members if m.status in ("pending", "confirmed")]
    holding = [m for m in members if m.status in LobbyMember.HOLDS_SPOT]  # invited friends keep their spot
    mine = next((m for m in members if m.user_id and me.is_authenticated and m.user_id == me.id), None)
    req = None
    if me.is_authenticated and not (mine and mine.status in ("pending", "confirmed")):
        req = lobby.requests.filter(user=me).first()
    if lobby.host_id == getattr(me, "id", None):
        role = "host"
    elif mine and mine.status in ("pending", "confirmed"):
        role = "member"
    elif mine and mine.status == "invited":
        role = "invited"
    elif req:
        role = {"pending": "requested", "declined": "declined"}.get(req.status)
    else:
        role = None
    fee = services.split_fee() if lobby.is_split else 0
    return {
        "id": lobby.id,
        "venue": {"id": lobby.venue_id, "name": lobby.venue.name, "area": lobby.venue.area.name,
                  "lat": lobby.venue.lat, "lng": lobby.venue.lng},
        "sport": {"id": lobby.sport_id, "name": lobby.sport.name, "fg": lobby.sport.fg_color, "bg": lobby.sport.bg_color},
        "court": {"id": lobby.court_id, "name": lobby.court.name},
        "date": lobby.date.isoformat(),
        "date_label": f"{lobby.date:%a, %-d %b}",
        "time_label": f"{fmt_hour(lobby.start_hour)} – {fmt_hour(lobby.end_hour)}",
        "start_hour": lobby.start_hour,
        "duration": lobby.duration,
        "starts_at": lobby.start_dt.isoformat(),
        "ends_at": lobby.end_dt.isoformat(),
        "capacity": lobby.capacity,
        "taken": len(holding),
        "spots_left": max(0, lobby.capacity - len(holding)),
        "paid_count": sum(1 for m in active if m.status == "confirmed"),
        "turf_price": lobby.turf_price,
        "share": lobby.share if lobby.is_split else 0,
        "fee": fee,
        "per_head": (lobby.share + fee) if lobby.is_split else 0,
        "payment_rule": lobby.payment_rule,
        "booking_mode": lobby.booking_mode,
        "is_public": lobby.is_public,
        "status": lobby.status,
        "status_label": lobby.get_status_display(),
        "slot_state": slot_state(lobby),
        "alert": lobby.alert,
        "host": {**person(lobby.host, me), **services.host_stats(lobby.host)},
        "avatars": [_initials(m.user) if m.user_id else (m.guest_name[:1].upper() or "G") for m in active[:5]],
        "my_role": role,
        "my_request_id": req.id if req else None,
        "invited_by": person(lobby.host, me) if role == "invited" else None,
    }


def member_payload(m, me, lobby):
    return {
        "id": m.id,
        "name": m.display_name,
        "initials": _initials(m.user) if m.user_id else (m.guest_name[:1].upper() or "G"),
        "user_id": m.user_id,
        "is_me": bool(m.user_id and m.user_id == me.id),
        "tag": m.tag,
        "status": m.status,
        "paid": m.status == "confirmed",
        "amount_due": m.amount_due if m.status == "pending" else 0,
        "pay_by": m.pay_by.isoformat() if m.pay_by and m.status == "pending" else None,
        "checked_in": m.checked_in_at is not None,
        "refund_due": m.refund_due,
    }


def lobby_detail(request, lobby):
    me = request.user
    data = lobby_card(lobby, me)
    in_room = services.can_enter_room(lobby, me) or lobby.host_id == me.id
    if not in_room:
        return data  # outsiders see the card only — never the squad, chat or booking
    now = timezone.now()
    mine = services.membership(lobby, me)
    is_host = lobby.host_id == me.id
    members = lobby.members.filter(status__in=LobbyMember.HOLDS_SPOT).select_related("user")
    b = lobby.booking
    data.update({
        "members": [member_payload(m, me, lobby) for m in members],
        "pool": {"pooled": lobby.pooled(), "target": lobby.turf_price},
        "booking": {
            "id": b.id, "code": b.code, "pin": b.checkin_pin, "status": b.status,
            "qr_payload": f"TURFLET|{b.code}|{b.venue_id}|{b.court_id}|{b.date.isoformat()}|{b.start_hour}|{b.duration}|{b.payment_status}",
        } if b and b.status in ("confirmed", "completed") else None,
        "held_booking": b.id if b and lobby.status == "draft" and is_host and b.status == "held" else None,
        "payout": {"status": lobby.payout_status, "label": lobby.get_payout_status_display(),
                   "trigger": lobby.payout_trigger,
                   "at": timezone.localtime(lobby.payout_at).strftime("%-d %b, %-I:%M %p") if lobby.payout_at else None},
        "pending_requests": lobby.requests.filter(status="pending").count() if is_host else 0,
        "me": {
            "member_id": mine.id if mine else None,
            "status": mine.status if mine else None,
            "tag": mine.tag if mine else None,
            "amount_due": mine.amount_due if mine and mine.status == "pending" else 0,
            "pay_by": mine.pay_by.isoformat() if mine and mine.pay_by and mine.status == "pending" else None,
            "checked_in": bool(mine and mine.checked_in_at),
            "can_pay": bool(mine and mine.status == "pending" and lobby.status in ("crowdfunding", "locked")),
            "can_checkin": bool(mine and mine.status == "confirmed" and lobby.status == "locked"
                                and lobby.start_dt - services.CHECKIN_WINDOW <= now <= lobby.start_dt + services.CHECKIN_WINDOW
                                and not mine.checked_in_at),
            "can_report": bool(mine and mine.tag != "host" and mine.status == "confirmed"
                               and lobby.start_dt <= now <= lobby.end_dt + services.RELEASE_AFTER),
            "can_leave": bool(mine and mine.tag != "host" and lobby.is_live and lobby.start_dt > now),
        },
        "host_actions": {
            "pay_balance": max(0, lobby.turf_price - lobby.pooled()) if lobby.status == "crowdfunding" else None,
            "can_switch": lobby.status == "crowdfunding" or (lobby.status == "draft" and b is None),
            "can_lock": lobby.status == "draft",
            "lock_amount": lobby.turf_price if lobby.status == "draft" else None,
            "can_unpublish": lobby.is_public and lobby.is_live,
            "can_cancel": lobby.is_live,
        } if is_host else None,
    })
    return data


def message_payload(msg, me, members=None):
    data = {
        "id": msg.id,
        "kind": msg.kind,
        "body": msg.body,
        "sender": person(msg.sender, me) if msg.sender_id else None,
        "at": timezone.localtime(msg.created_at).strftime("%-I:%M %p"),
    }
    if msg.kind == "payment" and msg.member_id:
        m = (members or {}).get(msg.member_id) or msg.member
        data["card"] = {
            "member_id": m.id,
            "name": m.display_name,
            "amount": m.amount_due if m.status == "pending" else m.amount_paid,
            "status": m.status,
            "pay_by": m.pay_by.isoformat() if m.pay_by and m.status == "pending" else None,
            "is_me": bool(m.user_id and m.user_id == me.id),
        }
    return data


def _messages(request, qs, lobby):
    after = request.GET.get("after")
    if after and after.isdigit():
        qs = qs.filter(id__gt=int(after))
    else:
        qs = qs.order_by("-id")[:80]
        qs = sorted(qs, key=lambda m: m.id)
    members = {m.id: m for m in lobby.members.select_related("user")}
    return [message_payload(m, request.user, members) for m in qs]


def _lobby(pk):
    return get_object_or_404(Lobby.objects.select_related("venue__area", "court", "sport", "host", "booking"), pk=pk)


def _room(request, pk):
    lobby = _lobby(pk)
    services.sync([lobby])
    lobby.refresh_from_db()
    if not (services.can_enter_room(lobby, request.user) or lobby.host_id == request.user.id):
        raise ValidationError({"lobby": "Only players in this match can see the Match Room."})
    return lobby


def _host_lobby(request, pk):
    lobby = _lobby(pk)
    if lobby.host_id != request.user.id:
        raise ValidationError({"lobby": "Only the host can do that."})
    return lobby


# ------------------------------------------------------------------ lists

@api_view(["GET", "POST"])
@permission_classes([permissions.IsAuthenticatedOrReadOnly])
def lobbies(request):
    """GET ?area= | ?city= → public lobbies with spots in that city. POST → Squad Builder."""
    if request.method == "POST":
        lobby, booking = services.create_lobby(request.user, request.data)
        data = lobby_detail(request, lobby)
        if booking is not None:
            from bookings.api import booking_payload
            data["checkout_booking"] = booking_payload(request, booking)
        return Response(data, status=201)
    city = None
    if request.GET.get("city"):
        city = City.objects.filter(pk=request.GET["city"]).first()
    elif request.GET.get("area"):
        area = Area.objects.filter(pk=request.GET["area"]).select_related("city").first()
        city = area.city if area else None
    if not city:
        return Response([])
    qs = services.upcoming_public(Lobby.objects.filter(venue__area__city=city, venue__is_active=True))
    if request.GET.get("sport"):
        qs = qs.filter(sport_id=request.GET["sport"])
    return Response([lobby_card(lb, request.user) for lb in qs[:50]])


@api_view(["GET"])
def venue_lobbies(request, pk):
    """Open lobbies at a venue, optionally for one slot: ?date=&start_hour=&court=&sport="""
    venue = get_object_or_404(Venue, pk=pk, is_active=True)
    qs = Lobby.objects.filter(venue=venue)
    p = request.GET
    if p.get("date"):
        qs = qs.filter(date=p["date"])
    if p.get("sport"):
        qs = qs.filter(sport_id=p["sport"])
    if p.get("court"):
        qs = qs.filter(court_id=p["court"])
    if p.get("start_hour", "").isdigit():
        h = int(p["start_hour"])
        qs = [lb for lb in services.upcoming_public(qs) if lb.start_hour <= h < lb.end_hour]
    else:
        qs = services.upcoming_public(qs)
    return Response([lobby_card(lb, request.user) for lb in qs])


@api_view(["GET"])
@permission_classes([Auth])
def my_lobbies(request):
    """Matches tab: hosting, playing and requested."""
    me = request.user
    member_of = Q(members__user=me, members__status__in=("pending", "confirmed")) | Q(host=me)
    qs = (Lobby.objects.filter(member_of).distinct()
          .select_related("venue__area", "court", "sport", "host", "booking"))
    services.sync(list(qs.filter(status__in=services.LIVE)))
    live = qs.filter(status__in=services.LIVE)
    past = qs.exclude(status__in=services.LIVE).order_by("-date", "-start_hour")[:20]
    reqs = (JoinRequest.objects.filter(user=me, status="pending", lobby__status__in=services.LIVE)
            .select_related("lobby__venue__area", "lobby__court", "lobby__sport", "lobby__host"))
    invites = (Lobby.objects.filter(members__user=me, members__status="invited", status__in=services.LIVE)
               .distinct().select_related("venue__area", "court", "sport", "host"))
    return Response({
        "upcoming": [lobby_card(lb, me) for lb in live.order_by("date", "start_hour")],
        # invites from friends first, then my requests to join other groups
        "requests": [lobby_card(lb, me) for lb in invites] + [lobby_card(r.lobby, me) for r in reqs],
        "past": [lobby_card(lb, me) for lb in past],
    })


@api_view(["GET"])
@permission_classes([Auth])
def players_lookup(request):
    """Squad Builder friend search: ?contact= email / mobile / referral code. Also returns recent co-players."""
    contact = request.GET.get("contact", "").strip()
    if contact:
        u = services.lookup_player(contact, request.user)
        return Response({"player": person(u, request.user)})
    return Response({"recent": [person(u, request.user) for u in services.recent_players(request.user)]})


# ------------------------------------------------------------------ one lobby

@api_view(["GET"])
def lobby_view(request, pk):
    lobby = _lobby(pk)
    services.sync([lobby])
    lobby.refresh_from_db()
    if request.user.is_authenticated:
        return Response(lobby_detail(request, lobby))
    return Response(lobby_card(lobby, request.user))


@api_view(["POST"])
@permission_classes([Auth])
def lobby_request(request, pk):
    req = services.request_join(_lobby(pk), request.user, request.data.get("message", ""))
    return Response(request_payload(req, request.user), status=201)


@api_view(["GET", "POST"])
@permission_classes([Auth])
def lobby_messages(request, pk):
    lobby = _room(request, pk)
    if request.method == "POST":
        msg = services.send(lobby, request.user, request.data.get("body"))
        return Response(message_payload(msg, request.user), status=201)
    return Response(_messages(request, LobbyMessage.objects.filter(lobby=lobby, request__isnull=True)
                              .select_related("sender"), lobby))


@api_view(["GET"])
@permission_classes([Auth])
def lobby_requests(request, pk):
    lobby = _host_lobby(request, pk)
    reqs = lobby.requests.select_related("user").order_by("status", "-created_at")
    return Response([request_payload(r, request.user) for r in reqs if r.status in ("pending", "approved", "declined")])


def request_payload(req, me):
    lobby = req.lobby
    last = req.messages.order_by("-id").first()
    return {
        "id": req.id,
        "status": req.status,
        "lobby": lobby_card(lobby, me),
        "player": {**person(req.user, me), **services.attendance(req.user),
                   "sports": [{"name": ps.sport.name, "level": ps.get_level_display()}
                              for ps in req.user.sports.select_related("sport")]},
        "last_message": last.body if last else "",
        "is_host": lobby.host_id == me.id,
    }


def _thread(request, pk, rid):
    req = get_object_or_404(JoinRequest.objects.select_related("lobby__venue__area", "lobby__court", "lobby__sport",
                                                               "lobby__host", "user"), pk=rid, lobby_id=pk)
    services.check_thread(req, request.user)
    return req


@api_view(["GET"])
@permission_classes([Auth])
def request_detail(request, pk, rid):
    return Response(request_payload(_thread(request, pk, rid), request.user))


@api_view(["GET", "POST"])
@permission_classes([Auth])
def request_messages(request, pk, rid):
    req = _thread(request, pk, rid)
    if request.method == "POST":
        msg = services.send(req.lobby, request.user, request.data.get("body"), req=req)
        return Response(message_payload(msg, request.user), status=201)
    return Response(_messages(request, req.messages.select_related("sender"), req.lobby))


@api_view(["POST"])
@permission_classes([Auth])
def request_decide(request, pk, rid, action):
    req = _thread(request, pk, rid)
    if action == "withdraw":
        services.withdraw(req, request.user)
    elif action in ("approve", "decline"):
        services.decide(req, request.user, approve=action == "approve")
    else:
        raise ValidationError({"action": "Unknown action."})
    req.refresh_from_db()
    return Response(request_payload(req, request.user))


@api_view(["GET", "POST"])
@permission_classes([Auth])
def lobby_pay(request, pk):
    """GET → split checkout breakdown, POST → pay my share into escrow."""
    lobby = _room(request, pk)
    if request.method == "GET":
        return Response(services.checkout(lobby, request.user))
    services.pay_share(lobby, request.user, request.data.get("method", "upi"), request.data.get("upi_id", ""))
    return Response(lobby_detail(request, _lobby(pk)))


@api_view(["POST"])
@permission_classes([Auth])
def lobby_action(request, pk, action):
    """Host: lock, pay-balance, switch-slot, unpublish, cancel. Player: accept-invite, decline-invite, leave, checkin, report."""
    lobby = _lobby(pk)
    d, me = request.data, request.user
    message = ""
    if action == "lock":
        from bookings.api import booking_payload
        booking = services.lock_turf(lobby, me)
        data = lobby_detail(request, _lobby(pk))
        data["checkout_booking"] = booking_payload(request, booking)
        data["message"] = "Slot held — finish paying to lock the turf."
        return Response(data)
    if action == "accept-invite":
        services.accept_invite(lobby, me)
        message = "You're in! Welcome to the Match Room."
    elif action == "decline-invite":
        services.decline_invite(lobby, me)
        message = "Invite declined."
    elif action == "pay-balance":
        services.pay_balance(lobby, me, d.get("method", "upi"), d.get("upi_id", ""))
        message = "Balance paid — the turf is locked."
    elif action == "switch-slot":
        services.switch_slot(lobby, me, d)
        message = "Match moved to the new slot."
    elif action == "unpublish":
        services.unpublish(lobby, me)
        message = "Lobby unpublished. Solo players were refunded."
    elif action == "cancel":
        services.cancel_lobby(lobby, me, d.get("reason", ""))
        message = "Match cancelled. Everyone who paid is refunded."
    elif action == "leave":
        outcome = services.leave(lobby, me)
        message = f"You left the match. Your share is {outcome}."
    elif action == "checkin":
        try:
            lat, lng = float(d.get("lat")), float(d.get("lng"))
        except (TypeError, ValueError):
            raise ValidationError({"checkin": "Location is required to check in."})
        services.checkin(lobby, me, lat, lng)
        message = "Checked in at the venue."
    elif action == "report":
        held = services.report_no_show(lobby, me, d.get("reason", ""))
        message = "Reported. The host's payout is on hold while support reviews it." if held else \
            "Reported. Support will look into it."
    else:
        raise ValidationError({"action": "Unknown action."})
    data = lobby_detail(request, _lobby(pk)) if (services.can_enter_room(lobby, me) or lobby.host_id == me.id) \
        else lobby_card(_lobby(pk), me)
    data["message"] = message
    return Response(data)


@api_view(["POST"])
@permission_classes([Auth])
def lobby_remove_member(request, pk, member_id):
    services.remove_member(_lobby(pk), request.user, member_id)
    return Response(lobby_detail(request, _lobby(pk)))
