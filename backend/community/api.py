from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from bookings.services import fmt_hour
from venues.models import Venue

from . import services
from .models import OpenGame, PlayerGroup

Auth = permissions.IsAuthenticated


def _initials(u):
    parts = [p for p in (u.name or "").split() if p]
    return "".join(p[0] for p in parts[:2]).upper() or u.email[:2].upper()


def _person(u, me):
    return {"id": u.id, "name": u.name or u.email.split("@")[0], "initials": _initials(u), "is_me": u.id == me.id}


def share_text(group):
    return (f"Join my group \"{group.name}\" on Turflet to play together. "
            f"Open the app → Profile → My groups → Join with code {group.invite_code}")


def group_summary(group, me):
    members = list(group.memberships.select_related("user"))
    return {
        "id": group.id,
        "name": group.name,
        "member_count": len(members),
        "is_admin": any(m.user_id == me.id and m.role == "admin" for m in members),
        "initials": [_initials(m.user) for m in members[:3]],
    }


def group_detail_payload(request, group):
    me = request.user
    data = group_summary(group, me)
    today = timezone.localdate()
    games = (group.games.filter(booking__status="confirmed", booking__date__gte=today)
             .select_related("booking__venue", "booking__sport", "booking__user")
             .order_by("booking__date", "booking__start_hour")[:5])
    data.update({
        "invite_code": group.invite_code,
        "share_text": share_text(group),
        "members": [{**_person(m.user, me), "role": m.role} for m in group.memberships.select_related("user")],
        "pending_invites": [i.contact for i in group.invites.all()] if data["is_admin"] else [],
        "upcoming": [{
            "booking_id": g.booking_id, "venue": g.booking.venue.name, "sport": g.booking.sport.name,
            "when": f"{g.booking.date:%a, %-d %b} · {fmt_hour(g.booking.start_hour)}",
            "booked_by": g.booking.user.name or "",
            "is_mine": g.booking.user_id == me.id,
        } for g in games],
    })
    return data


def _my_group(request, pk):
    group = get_object_or_404(PlayerGroup, pk=pk)
    services.membership(group, request.user)
    return group


@api_view(["GET", "POST"])
@permission_classes([Auth])
def groups(request):
    if request.method == "POST":
        g = services.create_group(request.user, request.data.get("name"))
        return Response(group_detail_payload(request, g), status=201)
    services.claim_invites(request.user)
    qs = PlayerGroup.objects.filter(memberships__user=request.user).distinct()
    return Response([group_summary(g, request.user) for g in qs])


@api_view(["GET"])
@permission_classes([Auth])
def group_detail(request, pk):
    return Response(group_detail_payload(request, _my_group(request, pk)))


@api_view(["POST"])
@permission_classes([Auth])
def group_add_member(request, pk):
    group = _my_group(request, pk)
    result, who = services.add_member(group, request.user, request.data.get("contact"))
    data = group_detail_payload(request, group)
    data["result"] = result
    data["message"] = (f"{who.name or who.email} added" if result == "added"
                       else f"Invite saved for {who} — they'll join when they sign in. Share the code too.")
    return Response(data)


@api_view(["POST"])
@permission_classes([Auth])
def group_remove_member(request, pk, user_id):
    group = _my_group(request, pk)
    services.remove_member(group, request.user, user_id)
    return Response(group_detail_payload(request, group))


@api_view(["POST"])
@permission_classes([Auth])
def group_leave(request, pk):
    services.leave_group(_my_group(request, pk), request.user)
    return Response({"left": True})


@api_view(["POST"])
@permission_classes([Auth])
def group_join(request):
    g = services.join_by_code(request.user, request.data.get("code"))
    return Response(group_detail_payload(request, g))


# ------------------------------------------------------------------ open games

def open_game_payload(game, me):
    b = game.booking
    joined = list(game.active_players().select_related("user"))
    return {
        "id": game.id,
        "booking_id": b.id,
        "sport": {"id": b.sport_id, "name": b.sport.name, "fg": b.sport.fg_color, "bg": b.sport.bg_color},
        "court": b.court.name,
        "date": b.date.isoformat(),
        "date_label": f"{b.date:%a, %-d %b}",
        "time_label": f"{fmt_hour(b.start_hour)} – {fmt_hour(b.end_hour)}",
        "host": (b.user.name or "Player").split(" ")[0],
        "total_players": game.total_players,
        "joined_count": 1 + len(joined),
        "spots_left": game.spots_left,
        "share": game.share,
        "players": [_person(b.user, me) | {"role": "host"}] + [_person(p.user, me) | {"role": "player"} for p in joined],
        "is_host": b.user_id == me.id if me.is_authenticated else False,
        "joined": any(p.user_id == me.id for p in joined) if me.is_authenticated else False,
    }


@api_view(["GET"])
def venue_open_games(request, pk):
    venue = get_object_or_404(Venue, pk=pk, is_active=True)
    return Response([open_game_payload(g, request.user) for g in services.open_games_at(venue)])


@api_view(["POST"])
@permission_classes([Auth])
def open_game_join(request, pk):
    game = get_object_or_404(OpenGame, pk=pk)
    game = services.join_open_game(game, request.user, request.data.get("method", "upi"), request.data.get("upi_id", ""))
    return Response(open_game_payload(game, request.user))


@api_view(["POST"])
@permission_classes([Auth])
def open_game_leave(request, pk):
    game = get_object_or_404(OpenGame, pk=pk)
    services.leave_open_game(game, request.user)
    return Response(open_game_payload(game, request.user))
