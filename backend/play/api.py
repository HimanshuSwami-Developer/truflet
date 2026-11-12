from datetime import date as date_cls

from django.conf import settings
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from accounts.models import User
from bookings.payments import get_provider
from bookings.services import fmt_hour
from core.api import image_url
from core.models import notify
from venues.models import Sport, Venue

from . import services as S
from .models import RSVP, FriendRequest, Fixture, Game, Group, GroupMember, Tournament, TournamentTeam

Auth = permissions.IsAuthenticated
APP = settings.PUBLIC_APP_URL


def sport_mini(request, s):
    return {"id": s.id, "name": s.name, "fg": s.fg_color, "bg": s.bg_color, "image": image_url(request, s.image)}


def person(u, meta=""):
    return {"id": u.id, "name": u.name or u.email.split("@")[0], "initials": u.initials, "meta": meta}


def day_label(d):
    today = timezone.localdate()
    if d == today:
        return "Today"
    if (d - today).days == 1:
        return "Tomorrow"
    return f"{d:%a}"


# =================================================================== squad: groups

def next_game(group):
    return group.games.filter(status="upcoming", date__gte=timezone.localdate()).order_by("date", "start_hour").first()


def group_card(request, g, user):
    ng = next_game(g)
    if ng:
        next_text = f"Next game: {day_label(ng.date)}, {fmt_hour(ng.start_hour)} · {ng.in_count} in"
    else:
        next_text = "No game planned · Start one"
    members = list(g.memberships.select_related("user")[:3])
    return {
        "id": g.id, "name": g.name, "slug": g.slug, "sport": sport_mini(request, g.sport),
        "image": image_url(request, g.image) or image_url(request, g.sport.image),
        "member_count": g.memberships.count(), "next": next_text, "has_next": bool(ng),
        "avatars": [m.user.initials for m in members],
    }


@api_view(["GET", "POST"])
@permission_classes([Auth])
def groups(request):
    if request.method == "POST":
        name = (request.data.get("name") or "").strip() or "My new group"
        sport = get_object_or_404(Sport, pk=request.data.get("sport_id"))
        g = Group.objects.create(name=name, sport=sport, created_by=request.user, area=request.user.home_area)
        GroupMember.objects.create(group=g, user=request.user, role="admin")
        return Response(group_card(request, g, request.user), status=201)
    qs = Group.objects.filter(memberships__user=request.user).select_related("sport").distinct().order_by("created_at")
    return Response([group_card(request, g, request.user) for g in qs])


def _member_or_404(request, pk):
    g = get_object_or_404(Group.objects.select_related("sport", "area"), pk=pk)
    if not g.memberships.filter(user=request.user).exists():
        raise PermissionDenied("You are not a member of this group.")
    return g


@api_view(["GET"])
@permission_classes([Auth])
def group_detail(request, pk):
    g = _member_or_404(request, pk)
    ng = next_game(g)
    rsvp_map = {}
    my_rsvp = None
    if ng:
        rsvp_map = {r.user_id: r for r in ng.rsvps.all()}
        mine = rsvp_map.get(request.user.id)
        my_rsvp = mine.response if mine else "pending"
    members = []
    for m in g.memberships.select_related("user"):
        u = m.user
        games = Game.objects.filter(group=g, rsvps__user=u, rsvps__response="in", status="completed").count()
        bits = [b for b in ["Admin" if m.role == "admin" else "", m.position, f"{games} games"] if b]
        r = rsvp_map.get(u.id)
        status = {"in": "Going", "maybe": "Maybe", "out": "Out"}.get(r.response if r else "", "No reply")
        members.append({"id": u.id, "name": "You" if u.id == request.user.id else (u.name or u.email.split("@")[0]),
                        "initials": "ME" if u.id == request.user.id else u.initials,
                        "meta": " · ".join(bits), "status": status if ng else ""})
    members.sort(key=lambda x: x["name"] != "You")
    data = {
        "id": g.id, "name": g.name, "sport": sport_mini(request, g.sport),
        "area": g.area.name if g.area else "", "member_count": len(members),
        "image": image_url(request, g.image) or image_url(request, g.sport.image),
        "invite_link": f"{APP}/g/{g.slug}", "slug": g.slug,
        "is_admin": g.memberships.filter(user=request.user, role="admin").exists(),
        "members": members,
        "next_game": None,
    }
    if ng:
        cover = ng.venue.cover or (ng.venue.photos.first().image if ng.venue.photos.exists() else None)
        data["next_game"] = {
            "id": ng.id, "name": ng.name, "day": day_label(ng.date).upper(),
            "venue": ng.venue.name, "venue_image": image_url(request, cover),
            "time": f"{fmt_hour(ng.start_hour)[:-3] if (ng.start_hour < 12) == ((ng.start_hour + ng.duration) % 24 < 12) else fmt_hour(ng.start_hour)} – {fmt_hour(ng.start_hour + ng.duration)}",
            "court": ng.court.name if ng.court else "",
            "slot_booked": bool(ng.booking_id and ng.booking.status == "confirmed"),
            "booking_id": ng.booking_id,
            "total_cost": ng.total_cost, "in_count": ng.in_count, "maybe_count": ng.maybe_count,
            "share": ng.share, "my_rsvp": my_rsvp,
        }
    return Response(data)


@api_view(["POST"])
@permission_classes([Auth])
def group_join(request, slug):
    g = get_object_or_404(Group, slug=slug)
    GroupMember.objects.get_or_create(group=g, user=request.user)
    return Response({"id": g.id})


@api_view(["POST"])
@permission_classes([Auth])
def rsvp(request, pk):
    game = get_object_or_404(Game, pk=pk)
    resp = request.data.get("response")
    if resp not in ("in", "maybe", "out"):
        raise ValidationError({"response": "Use in, maybe or out."})
    if game.group and not game.group.memberships.filter(user=request.user).exists():
        if not game.rsvps.filter(user=request.user).exists():
            raise PermissionDenied("You were not invited to this game.")
    RSVP.objects.update_or_create(game=game, user=request.user, defaults={"response": resp})
    return Response({"in_count": game.in_count, "maybe_count": game.maybe_count, "share": game.share,
                     "my_rsvp": resp})


# =================================================================== squad: friends

@api_view(["GET"])
@permission_classes([Auth])
def friends(request):
    me = request.user
    out = []
    for u in FriendRequest.friends_of(me):
        shared = Group.objects.filter(memberships__user=me).filter(memberships__user=u).distinct()
        sports = ", ".join(ps.sport.name for ps in u.sports.select_related("sport")[:2]) or "Player"
        games = Game.objects.filter(rsvps__user=me, rsvps__response="in").filter(
            rsvps__user=u).distinct().count()
        meta = f"{sports} · " + (shared[0].name if shared.count() == 1 else f"{shared.count()} groups"
                                 if shared.count() > 1 else f"{games} games together")
        out.append(person(u, meta))
    return Response(out)


@api_view(["GET"])
@permission_classes([Auth])
def friend_requests(request):
    me = request.user
    my_friends = set(FriendRequest.friends_of(me).values_list("id", flat=True))
    out = []
    for fr in me.received_requests.filter(status="pending").select_related("from_user"):
        u = fr.from_user
        theirs = set(FriendRequest.friends_of(u).values_list("id", flat=True))
        mutual = len(my_friends & theirs)
        sport = u.sports.select_related("sport").first()
        meta = (f"{mutual} mutual friends" if mutual else "New on Turflet") + (f" · {sport.sport.name}" if sport else "")
        out.append({**person(u, meta), "request_id": fr.id})
    return Response(out)


@api_view(["POST"])
@permission_classes([Auth])
def friend_request_action(request, pk, action):
    fr = get_object_or_404(FriendRequest, pk=pk, to_user=request.user, status="pending")
    fr.status = "accepted" if action == "accept" else "declined"
    fr.save(update_fields=["status", "updated_at"])
    if fr.status == "accepted":
        notify(fr.from_user, "Friend request accepted", f"{request.user.name} is now your friend", "squad")
    return Response({"status": fr.status})


@api_view(["GET"])
@permission_classes([Auth])
def nearby(request):
    me = request.user
    exclude = set(FriendRequest.friends_of(me).values_list("id", flat=True)) | {me.id}
    sent = dict(me.sent_requests.filter(status="pending").values_list("to_user_id", "id"))
    qs = User.objects.filter(is_active=True, show_to_nearby=True).exclude(id__in=exclude)
    if me.home_area_id:
        qs = qs.filter(home_area__city_id=me.home_area.city_id)
    out = []
    for u in qs.prefetch_related("sports__sport")[:30]:
        ps = u.sports.all()[:1]
        km = None
        if None not in (me.lat, me.lng, u.lat, u.lng):
            from venues.models import Venue as V
            km = V(lat=u.lat, lng=u.lng).distance_km(me.lat, me.lng)
        level = ps[0].get_level_display() if ps else "Player"
        sport = ps[0].sport if ps else None
        out.append({
            **person(u), "sport": sport_mini(request, sport) if sport else None,
            "level": level + (f" · {km} km" if km is not None else ""), "requested": u.id in sent,
            "_km": km if km is not None else 999,
        })
    out.sort(key=lambda x: x.pop("_km"))
    return Response(out[:10])


@api_view(["POST"])
@permission_classes([Auth])
def add_friend(request, user_id):
    other = get_object_or_404(User, pk=user_id)
    if other == request.user:
        raise ValidationError({"user": "That's you!"})
    existing = FriendRequest.objects.filter(from_user=request.user, to_user=other).first()
    if existing and existing.status == "pending":
        existing.delete()
        return Response({"requested": False})
    reverse = FriendRequest.objects.filter(from_user=other, to_user=request.user, status="pending").first()
    if reverse:
        reverse.status = "accepted"
        reverse.save()
        return Response({"requested": False, "friends": True})
    FriendRequest.objects.update_or_create(from_user=request.user, to_user=other, defaults={"status": "pending"})
    notify(other, "New friend request", f"{request.user.name or 'A player'} wants to play with you", "squad")
    return Response({"requested": True})


# =================================================================== tournaments

def score_text(f, side, short=False):
    t = f.tournament
    if t.sport.scoring != "cricket":
        return str(getattr(f, f"{side}_runs")) if f.state in ("live", "done") else ""
    runs, wkts, balls = (getattr(f, f"{side}_{k}") for k in ("runs", "wkts", "balls"))
    if f.state not in ("live", "done"):
        return ""
    batted = balls > 0 or runs > 0 or wkts > 0
    if f.state == "live":
        if not batted and S.batting_side(f) != side:
            return "Yet to bat"
        overs = str(balls // 6) if balls % 6 == 0 else S.overs_text(balls)
        return f"{runs}/{wkts} ({overs})"
    return f"{runs}/{wkts}"


def fixture_payload(f):
    t = f.tournament
    tag = {"done": "FT", "live": "LIVE", "next": "NEXT", "tbd": "FINAL" if not f.next_fixture_id and f.stage == "ko" else "TBD"}[f.state]
    when = timezone.localtime(f.scheduled_at).strftime("%-I:%M %p") if f.scheduled_at else ""
    if f.state == "done":
        meta = f.court_label
    elif f.state == "live":
        meta = f"{f.court_label} · now"
    else:
        meta = " · ".join(x for x in [when, f.court_label] if x)
    data = {
        "id": f.id, "label": f.label, "round": f.round_name, "stage": f.stage, "group": f.group_label,
        "state": f.state, "tag": tag, "meta": meta,
        "a": S.qualifier_label(f.name_a), "b": S.qualifier_label(f.name_b),
        "a_score": score_text(f, "a"), "b_score": score_text(f, "b"),
        "winner": "a" if f.winner_id and f.winner_id == f.team_a_id else "b" if f.winner_id else None,
        "result": f.result_text,
        "can_start": f.state == "next" and bool(f.team_a_id and f.team_b_id),
    }
    if f.state == "live":
        data["live"] = live_payload(f)
    return data


def live_payload(f):
    t = f.tournament
    if t.sport.scoring != "cricket":
        res = S.points_result(f)
        return {"scoring": "points", "a_points": f.a_runs, "b_points": f.b_runs, "a": f.name_a, "b": f.name_b,
                "result": res["text"] if res else None, "can_undo": bool(f.history)}
    bat = S.batting_side(f)
    bowl = "b" if bat == "a" else "a"
    name = {"a": f.name_a, "b": f.name_b}
    runs, wkts, balls = (getattr(f, f"{bat}_{k}") for k in ("runs", "wkts", "balls"))
    res = S.cricket_result(f)
    max_b = t.overs * 6
    if f.innings == 2:
        target = getattr(f, f"{bowl}_runs") + 1
        need, left = target - runs, max_b - balls
        other_line = f"{name[bowl]} {getattr(f, f'{bowl}_runs')}/{getattr(f, f'{bowl}_wkts')} ({S.overs_text(getattr(f, f'{bowl}_balls')).replace('.0', '')})"
        equation = "Innings complete" if res else (
            f"Need {need} off {left} balls · RRR {need / (left / 6):.1f}" if left else "Last ball")
        summary = f"{name[bat].split(' ')[-1]} need {need} off {left} balls" if not res else res["text"]
    else:
        target = None
        other_line = f"{name[bowl]} yet to bat"
        rr = runs / (balls / 6) if balls else 0
        equation = f"First innings · RR {rr:.1f}"
        summary = f"{name[bat]} batting first"
    return {
        "scoring": "cricket", "batting": name[bat], "runs": runs, "wkts": wkts, "overs": S.overs_text(balls),
        "other_line": other_line, "target": target, "equation": equation, "summary": summary,
        "innings": f.innings, "result": res["text"] if res else None, "result_side": res["side"] if res else None,
        "can_undo": bool(f.history), "max_overs": t.overs,
    }


def tournament_card(request, t, user=None):
    cover = t.cover or t.sport.image
    filled = t.teams.count()
    my_team = t.teams.filter(captain=user).first() if user and user.is_authenticated else None
    return {
        "id": t.id, "name": t.name, "slug": t.slug, "sport": sport_mini(request, t.sport),
        "format": t.format, "format_label": t.get_format_display().split(" (")[0],
        "status": t.status, "team_count": t.team_count, "filled": filled, "spots_left": max(0, t.team_count - filled),
        "entry_fee": t.entry_fee, "prize_pool": t.prize_pool,
        "fee_label": f"₹{t.entry_fee:,}/{'pair' if t.players_per_team <= 2 else 'team'}" if t.entry_fee else "Free",
        "when": f"{'Starts ' if t.format == 'league' else ''}{t.start_date:%a %-d %b} · {t.team_count} {'pairs' if t.players_per_team <= 2 else 'teams'}" + (f" · {t.get_format_display().split(' (')[0]}" if t.format != "groups" else " · Groups"),
        "venue": t.venue.name, "image": image_url(request, cover),
        "registered": bool(my_team), "is_host": bool(user and t.host_id == user.id),
    }


def _host_or_403(request, t):
    if t.host_id != request.user.id and not request.user.is_staff:
        raise PermissionDenied("Only the host can do that.")


@api_view(["POST"])
@permission_classes([Auth])
def plan(request):
    d = request.data
    sport = get_object_or_404(Sport, pk=d.get("sport_id"))
    venue = get_object_or_404(Venue, pk=d.get("venue_id"))
    return Response(S.plan(sport, venue, d.get("format", "ko"), int(d.get("teams", 8)), d.get("window", "full"),
                           int(d.get("entry_fee", 0))))


@api_view(["GET", "POST"])
@permission_classes([Auth])
def tournaments(request):
    if request.method == "GET":
        qs = Tournament.objects.filter(status="open").exclude(host=request.user).select_related("sport", "venue")
        if request.user.home_area_id:
            qs = qs.filter(venue__area__city_id=request.user.home_area.city_id)
        return Response([tournament_card(request, t, request.user) for t in qs[:20]])
    d = request.data
    sport = get_object_or_404(Sport, pk=d.get("sport_id"))
    venue = get_object_or_404(Venue, pk=d.get("venue_id"))
    fmt = d.get("format", "ko")
    teams = int(d.get("teams", 8))
    if fmt not in dict(Tournament.FORMATS) or teams not in (4, 8, 16):
        raise ValidationError({"format": "Pick a format and 4, 8 or 16 teams."})
    name = (d.get("name") or "").strip()
    if not name:
        raise ValidationError({"name": "Please add a name to continue."})
    try:
        start = date_cls.fromisoformat(d.get("start_date", ""))
    except ValueError:
        raise ValidationError({"start_date": "Pick a start date."})
    fee = int(d.get("entry_fee", 0))
    window = d.get("window", "full")
    p = S.plan(sport, venue, fmt, teams, window, fee)
    t = Tournament.objects.create(
        name=name, sport=sport, host=request.user, format=fmt, team_count=teams,
        players_per_team=int(d.get("players_per_team", sport.team_size)), entry_fee=fee,
        prize_pool=max(0, p["left_for_prizes"]), venue=venue, start_date=start, window=window, status="open",
    )
    return Response({**tournament_card(request, t, request.user), "link": f"{APP}/t/{t.slug}", "plan": p},
                    status=201)


@api_view(["GET"])
@permission_classes([Auth])
def tournament_detail(request, pk):
    return Response(tournament_payload(request, pk))


def tournament_payload(request, pk):
    t = get_object_or_404(Tournament.objects.select_related("sport", "venue", "host"), pk=pk)
    rounds = []
    for f in t.fixtures.select_related("team_a", "team_b", "winner", "tournament__sport").order_by("round_index", "stage", "order"):
        key = f"{f.round_name}" + (f" · Group {f.group_label}" if f.group_label else "")
        if not rounds or rounds[-1]["key"] != key:
            day = timezone.localtime(f.scheduled_at).date() if f.scheduled_at else None
            when = ""
            if day:
                idx = (day - t.start_date).days + 1
                when = "Today" if day == timezone.localdate() else f"Day {idx}"
                if not f.next_fixture_id and f.stage == "ko" and f.scheduled_at:
                    when += f" {timezone.localtime(f.scheduled_at):%-I %p}"
            rounds.append({"key": key, "name": f"{key} · {when}" if when else key, "matches": []})
        rounds[-1]["matches"].append(fixture_payload(f))
    for r in rounds:
        r["cols"] = 2 if len(r["matches"]) >= 4 else 1
    teams = []
    for tm in t.teams.all():
        teams.append({
            "id": tm.id, "name": tm.name, "initials": tm.initials,
            "captain": tm.captain_name or (tm.captain.name if tm.captain else ""),
            "status": S.team_status(tm), "paid": tm.paid, "reminded": bool(tm.reminded_at),
            "is_mine": tm.captain_id == request.user.id,
        })
    live = t.fixtures.filter(state="live").first()
    data = {
        **tournament_card(request, t, request.user),
        "venue_id": t.venue_id, "players_per_team": t.players_per_team, "window": t.get_window_display(),
        "overs": t.overs, "scoring": t.sport.scoring,
        "day_label": _day_of(t), "played": t.played_matches, "total_matches": t.total_matches or S.match_count(t.format, t.team_count),
        "collected": t.collected, "link": f"{APP}/t/{t.slug}",
        "rounds": rounds, "teams": teams, "pending_payments": sum(1 for x in teams if not x["paid"]),
        "has_fixtures": bool(rounds), "live_fixture_id": live.id if live else None,
        "standings": [
            {"team": r["team"].name, "played": r["played"], "won": r["won"], "points": r["points"]}
            for r in S.standings(t)
        ] if t.format == "league" and rounds else [],
    }
    return data


def _day_of(t):
    if t.status != "live":
        return t.get_status_display().upper()
    d = (timezone.localdate() - t.start_date).days + 1
    return f"LIVE · DAY {max(1, d)}"


@api_view(["POST", "DELETE"])
@permission_classes([Auth])
def tournament_register(request, pk):
    t = get_object_or_404(Tournament, pk=pk)
    if request.method == "DELETE":
        team = t.teams.filter(captain=request.user).first()
        if team and not t.fixtures.exists():
            team.delete()
        return Response(tournament_card(request, t, request.user))
    S.register_team(t, request.user, request.data.get("team_name"))
    return Response(tournament_card(request, t, request.user), status=201)


@api_view(["POST"])
@permission_classes([Auth])
def team_pay(request, pk, team_id):
    team = get_object_or_404(TournamentTeam, pk=team_id, tournament_id=pk)
    if team.captain_id != request.user.id and team.tournament.host_id != request.user.id:
        raise PermissionDenied("Only the captain can pay the entry fee.")
    if not team.paid:
        res = get_provider().charge_amount(team.tournament.entry_fee, request.data.get("method", "upi"), team.id)
        if not res.success:
            raise ValidationError({"payment": res.message})
        team.paid, team.paid_at = True, timezone.now()
        team.save(update_fields=["paid", "paid_at"])
    return Response({"paid": True})


@api_view(["POST"])
@permission_classes([Auth])
def tournament_add_team(request, pk):
    t = get_object_or_404(Tournament, pk=pk)
    _host_or_403(request, t)
    name = (request.data.get("name") or "").strip()
    if not name:
        raise ValidationError({"name": "Team name is required."})
    if t.teams.count() >= t.team_count:
        raise ValidationError({"team": "All spots are taken."})
    TournamentTeam.objects.create(tournament=t, name=name, captain_name=request.data.get("captain_name", ""),
                                  paid=bool(request.data.get("paid")))
    return Response(tournament_payload(request, pk))


@api_view(["POST"])
@permission_classes([Auth])
def tournament_generate(request, pk):
    t = get_object_or_404(Tournament, pk=pk)
    _host_or_403(request, t)
    if t.fixtures.filter(state__in=["live", "done"]).exists():
        raise ValidationError({"fixtures": "Matches have already started."})
    S.generate_fixtures(t)
    return Response(tournament_payload(request, pk))


@api_view(["POST"])
@permission_classes([Auth])
def tournament_remind(request, pk):
    t = get_object_or_404(Tournament, pk=pk)
    _host_or_403(request, t)
    n = 0
    for team in t.teams.filter(paid=False):
        team.reminded_at = timezone.now()
        team.save(update_fields=["reminded_at"])
        notify(team.captain, f"Entry fee pending · {t.name}", f"Pay ₹{t.entry_fee:,} to confirm {team.name}", "tournament")
        n += 1
    return Response({"reminded": n})


def _fixture_for_host(request, pk):
    f = get_object_or_404(Fixture.objects.select_related("tournament__sport", "team_a", "team_b"), pk=pk)
    _host_or_403(request, f.tournament)
    return f


@api_view(["POST"])
@permission_classes([Auth])
def fixture_action(request, pk, action):
    f = _fixture_for_host(request, pk)
    d = request.data
    if action == "start":
        S.start_match(f)
    elif action == "ball":
        S.score_ball(f, runs=int(d.get("runs", 0)), wicket=int(d.get("wicket", 0)), legal=int(d.get("legal", 1)),
                     side=d.get("side"))
    elif action == "undo":
        S.undo(f)
    elif action == "end-innings":
        S.end_innings(f)
    elif action == "confirm":
        S.confirm_result(f, d.get("winner"))
    else:
        raise ValidationError({"action": "Unknown action"})
    f.refresh_from_db()
    return Response(fixture_payload(f))


# =================================================================== quick matches

@api_view(["POST"])
@permission_classes([Auth])
def create_game(request):
    from venues.models import VenueSport
    d = request.data
    sport = get_object_or_404(Sport, pk=d.get("sport_id"))
    venue = get_object_or_404(Venue, pk=d.get("venue_id"))
    group = Group.objects.filter(pk=d.get("group_id"), memberships__user=request.user).first() if d.get("group_id") else None
    try:
        day = date_cls.fromisoformat(d.get("date", ""))
        start = int(d.get("start_hour"))
    except (TypeError, ValueError):
        raise ValidationError({"date": "Pick a date and time."})
    name = (d.get("name") or "").strip()
    if not name:
        raise ValidationError({"name": "Please add a name to continue."})
    vs = VenueSport.objects.filter(venue=venue, sport=sport).first() or venue.venue_sports.first()
    cost = vs.price_for(start) if vs else 0
    game = Game.objects.create(
        name=name, sport=sport, group=group, venue=venue, date=day, start_hour=start, duration=1,
        per_side=int(d.get("per_side", sport.team_size)), auto_balance=bool(d.get("auto_balance", True)),
        total_cost=cost, created_by=request.user,
        court=venue.courts.filter(sports=sport).first() or venue.courts.first(),
    )
    RSVP.objects.create(game=game, user=request.user, response="in")
    invited = 0
    if group:
        for m in group.memberships.exclude(user=request.user).select_related("user"):
            RSVP.objects.get_or_create(game=game, user=m.user)
            notify(m.user, f"New game in {group.name}", f"{name} · {day:%a %-d %b} {fmt_hour(start)}", "squad")
            invited += 1
    return Response({"id": game.id, "link": f"{APP}/m/{game.slug}", "invited": invited,
                     "invited_to": group.name if group else "friends", "venue_id": venue.id,
                     "court_id": game.court_id, "sport_id": sport.id, "date": day.isoformat(),
                     "start_hour": start}, status=201)


# =================================================================== play home

def game_item(request, g, user):
    meta_bits = ["Friendly", f"{day_label(g.date)} {fmt_hour(g.start_hour)}", g.venue.name.split(" ")[0]]
    if g.status == "completed":
        meta_bits = ["Friendly", f"{g.date:%-d %b}", g.result] if g.result else ["Friendly", f"{g.date:%-d %b}"]
        status = "Won" if g.won else "Lost" if g.won is False else "Played"
    else:
        status = "Match"
    return {"kind": "game", "id": g.id, "title": g.name, "meta": " · ".join(b for b in meta_bits if b),
            "status": status, "sport": sport_mini(request, g.sport), "group_id": g.group_id}


def tour_item(request, t, user):
    if t.status == "completed":
        champ = t.fixtures.filter(stage="ko", next_fixture__isnull=True, state="done").first()
        won = bool(champ and champ.winner and champ.winner.captain_id == user.id)
        status = "Won" if won else "Played"
        meta = f"{t.sport.name} · {t.team_count} teams · {t.start_date:%b}"
    else:
        status = {"live": "Live", "draft": "Draft", "open": "Open"}[t.status]
        day = ""
        if t.status == "live":
            last_day = t.fixtures.order_by("-scheduled_at").first()
            total_days = ((timezone.localtime(last_day.scheduled_at).date() - t.start_date).days + 1) if last_day and last_day.scheduled_at else 1
            cur = max(1, (timezone.localdate() - t.start_date).days + 1)
            day = f" · Day {cur} of {total_days}"
        meta = f"{t.team_count} teams · {t.get_format_display().split(' (')[0]}{day}"
    return {"kind": "tournament", "id": t.id, "title": t.name, "meta": meta, "status": status,
            "sport": sport_mini(request, t.sport)}


@api_view(["GET"])
@permission_classes([Auth])
def play_home(request):
    u = request.user
    today = timezone.localdate()
    my_games = Game.objects.filter(Q(rsvps__user=u) | Q(created_by=u)).distinct().select_related("sport", "venue")
    hosting = Tournament.objects.filter(host=u).exclude(status="completed").select_related("sport", "venue")
    joined = Tournament.objects.filter(teams__captain=u).distinct().select_related("sport", "venue")

    upcoming = [game_item(request, g, u) for g in my_games.filter(status="upcoming", date__gte=today)]
    upcoming += [tour_item(request, t, u) for t in joined.exclude(status="completed")]
    past = [game_item(request, g, u) for g in my_games.filter(status="completed").order_by("-date")[:10]]
    past += [tour_item(request, t, u) for t in Tournament.objects.filter(Q(teams__captain=u) | Q(host=u), status="completed").distinct()[:10]]

    live = None
    lf = Fixture.objects.filter(tournament__host=u, state="live").select_related("tournament__sport", "team_a", "team_b").first()
    if lf:
        lp = live_payload(lf)
        live = {
            "tournament_id": lf.tournament_id, "tournament": lf.tournament.name, "round": f"{lf.round_name.rstrip('s')} {lf.order + 1}" if lf.stage == "ko" and lf.round_name != "Final" else lf.round_name,
            "a": lf.name_b if lp.get("batting") == lf.name_b else lf.name_a,
            "a_score": score_text(lf, "b" if lp.get("batting") == lf.name_b else "a"),
            "b": lf.name_a if lp.get("batting") == lf.name_b else lf.name_b,
            "b_score": score_text(lf, "a" if lp.get("batting") == lf.name_b else "b"),
            "summary": lp.get("summary") or lp.get("result") or "",
        }
    open_ts = Tournament.objects.filter(status="open").exclude(host=u).select_related("sport", "venue")
    if u.home_area_id:
        open_ts = open_ts.filter(venue__area__city_id=u.home_area.city_id)
    return Response({
        "live": live,
        "upcoming": upcoming,
        "hosting": [tour_item(request, t, u) for t in hosting],
        "past": past,
        "open_tournaments": [tournament_card(request, t, u) for t in open_ts[:10]],
    })
