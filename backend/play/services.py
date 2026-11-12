"""Tournament planning, fixture generation, scheduling and live scoring."""
import math
import random
import re
from datetime import datetime, timedelta

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from core.models import notify

from .models import Fixture, Tournament, TournamentTeam

KO_NAMES = {2: ("Final", "F"), 4: ("Semi-finals", "SF"), 8: ("Quarter-finals", "QF"), 16: ("Round of 16", "R16-")}
QUALIFIER_RE = re.compile(r"^([A-H])([12])$")


# ------------------------------------------------------------------ planning maths (mirrors the app)

def match_count(fmt, n):
    if fmt == "ko":
        return n - 1
    if fmt == "league":
        return n * (n - 1) // 2
    return (n // 4) * 6 + (n // 2 - 1)


def plan(sport, venue, fmt, teams, window, entry_fee):
    matches = match_count(fmt, teams)
    hours_per_match = sport.match_minutes / 60
    start, end = Tournament.WINDOW_HOURS[window]
    courts = max(1, venue.courts.filter(is_active=True, sports=sport).count() or venue.courts.count())
    per_day = int((end - start) // hours_per_match) * courts
    days = max(1, math.ceil(matches / max(1, per_day)))
    court_hours = math.ceil(matches * hours_per_match)
    vs = venue.venue_sports.filter(sport=sport).first()
    price = vs.base_price if vs else 0
    venue_cost = court_hours * price
    collected = entry_fee * teams
    return {
        "matches": matches, "days": days, "per_day": per_day, "courts": courts,
        "court_hours": court_hours, "venue_cost": venue_cost, "collected": collected,
        "left_for_prizes": collected - venue_cost,
    }


def qualifier_label(token):
    m = QUALIFIER_RE.match(token or "")
    if not m:
        return token
    return f"Group {m.group(1)} {'winner' if m.group(2) == '1' else 'runner-up'}"


# ------------------------------------------------------------------ fixture generation

def _round_robin(teams):
    """Circle method. Returns list of rounds, each a list of (a, b)."""
    items = list(teams)
    if len(items) % 2:
        items.append(None)
    n = len(items)
    rounds = []
    for _ in range(n - 1):
        pairs = [(items[i], items[n - 1 - i]) for i in range(n // 2)]
        rounds.append([p for p in pairs if p[0] is not None and p[1] is not None])
        items = [items[0]] + [items[-1]] + items[1:-1]
    return rounds


def _build_ko(t, first_round_pairs, start_round_index, placeholders=None):
    """Create a full knockout bracket. first_round_pairs: list of (team|None, team|None)."""
    size = len(first_round_pairs) * 2
    created_rounds = []
    ri = start_round_index
    current = []
    name, prefix = KO_NAMES.get(size, (f"Round of {size}", f"R{size}-"))
    for i, (a, b) in enumerate(first_round_pairs):
        pa, pb = (placeholders[i] if placeholders else ("", ""))
        f = Fixture.objects.create(
            tournament=t, stage="ko", round_index=ri, round_name=name, order=i,
            label=f"{prefix}{i + 1}" if size > 2 else "F",
            team_a=a, team_b=b, placeholder_a=pa, placeholder_b=pb,
            state="next" if a and b else "tbd",
        )
        current.append(f)
    created_rounds.append(current)
    while len(current) > 1:
        ri += 1
        size //= 2
        name, prefix = KO_NAMES.get(size, (f"Round of {size}", f"R{size}-"))
        nxt = []
        for i in range(len(current) // 2):
            fa, fb = current[2 * i], current[2 * i + 1]
            f = Fixture.objects.create(
                tournament=t, stage="ko", round_index=ri, round_name=name, order=i,
                label=f"{prefix}{i + 1}" if size > 2 else "F",
                placeholder_a=f"Winner {fa.label}", placeholder_b=f"Winner {fb.label}", state="tbd",
            )
            Fixture.objects.filter(pk=fa.pk).update(next_fixture=f, next_slot="a")
            Fixture.objects.filter(pk=fb.pk).update(next_fixture=f, next_slot="b")
            nxt.append(f)
        created_rounds.append(nxt)
        current = nxt
    return created_rounds


@transaction.atomic
def generate_fixtures(t, shuffle=True):
    teams = list(t.teams.all())
    if len(teams) < 2:
        raise ValidationError({"teams": "At least 2 teams are needed to make fixtures."})
    if t.format in ("ko", "groups") and len(teams) not in (4, 8, 16):
        raise ValidationError({"teams": "Knockout formats need exactly 4, 8 or 16 teams."})
    t.fixtures.all().delete()
    if shuffle:
        random.shuffle(teams)
    for i, team in enumerate(teams):
        team.seed, team.group_label, team.eliminated = i, "", False
        team.save(update_fields=["seed", "group_label", "eliminated"])

    if t.format == "ko":
        pairs = [(teams[2 * i], teams[2 * i + 1]) for i in range(len(teams) // 2)]
        _build_ko(t, pairs, 0)
    elif t.format == "league":
        for ri, rnd in enumerate(_round_robin(teams)):
            for oi, (a, b) in enumerate(rnd):
                Fixture.objects.create(tournament=t, stage="league", round_index=ri, round_name=f"Round {ri + 1}",
                                       order=oi, team_a=a, team_b=b, state="next")
    else:  # groups of 4 + knockout
        letters = "ABCDEFGH"
        groups = [teams[i:i + 4] for i in range(0, len(teams), 4)]
        order = 0
        for gi, g in enumerate(groups):
            label = letters[gi]
            for team in g:
                team.group_label = label
                team.save(update_fields=["group_label"])
            for rnd in _round_robin(g):
                for a, b in rnd:
                    Fixture.objects.create(tournament=t, stage="group", round_index=0, round_name="Group stage",
                                           order=order, group_label=label, team_a=a, team_b=b, state="next")
                    order += 1
        g = len(groups)
        if g == 1:
            ph = [("A1", "A2")]
        elif g == 2:
            ph = [("A1", "B2"), ("B1", "A2")]
        else:
            ph = [("A1", "B2"), ("C1", "D2"), ("B1", "A2"), ("D1", "C2")]
        _build_ko(t, [(None, None)] * len(ph), 1, placeholders=ph)
    schedule(t)
    return t.fixtures.all()


def schedule(t):
    """Assign court and start time to every fixture inside the daily window."""
    hours_per_match = t.sport.match_minutes / 60
    start_h, end_h = t.window_hours
    court_names = list(t.venue.courts.filter(is_active=True).values_list("name", flat=True)) or ["Court A"]
    slots_per_day = max(1, int((end_h - start_h) // hours_per_match))
    tz = timezone.get_current_timezone()
    day, slot, court = 0, 0, 0
    last_round = None
    for f in t.fixtures.order_by("round_index", "order"):
        key = (f.stage, f.round_index)
        if last_round is not None and key != last_round and court != 0:
            court, slot = 0, slot + 1  # a new round starts on a fresh time slot
        if slot >= slots_per_day:
            day, slot = day + 1, 0
        last_round = key
        base = timezone.make_aware(datetime.combine(t.start_date + timedelta(days=day), datetime.min.time()), tz)
        f.scheduled_at = base + timedelta(hours=start_h + slot * hours_per_match)
        f.court_label = court_names[court % len(court_names)]
        f.save(update_fields=["scheduled_at", "court_label"])
        court += 1
        if court >= len(court_names):
            court, slot = 0, slot + 1


# ------------------------------------------------------------------ live scoring

def max_wickets(t):
    return max(1, min(10, t.players_per_team - 1))


def batting_side(f):
    first = f.batting_first
    return first if f.innings == 1 else ("b" if first == "a" else "a")


def _get(f, side, key):
    return getattr(f, f"{side}_{key}")


def _add(f, side, key, delta):
    setattr(f, f"{side}_{key}", max(0, getattr(f, f"{side}_{key}") + delta))


def overs_text(balls):
    return f"{balls // 6}.{balls % 6}"


def cricket_result(f):
    """Returns dict(winner_side, text) or None while the match is in progress."""
    t = f.tournament
    max_b, max_w = t.overs * 6, max_wickets(t)
    first = f.batting_first
    second = "b" if first == "a" else "a"
    if f.innings == 1:
        return None
    target = _get(f, first, "runs") + 1
    runs, wkts, balls = _get(f, second, "runs"), _get(f, second, "wkts"), _get(f, second, "balls")
    name = {"a": f.name_a, "b": f.name_b}
    if runs >= target:
        return {"side": second, "text": f"{name[second]} won by {max_w - wkts} wickets"}
    if wkts >= max_w or balls >= max_b:
        if runs == target - 1:
            return {"side": None, "text": "Scores level — play a super over"}
        return {"side": first, "text": f"{name[first]} won by {target - 1 - runs} runs"}
    return None


def points_result(f):
    if f.a_runs == f.b_runs:
        return None
    side = "a" if f.a_runs > f.b_runs else "b"
    name = f.name_a if side == "a" else f.name_b
    return {"side": side, "text": f"{name} won {max(f.a_runs, f.b_runs)}–{min(f.a_runs, f.b_runs)}"}


def start_match(f):
    if f.state not in ("next",) or not (f.team_a and f.team_b):
        raise ValidationError({"fixture": "Both teams must be known before starting."})
    f.state = "live"
    f.save(update_fields=["state"])
    t = f.tournament
    if t.status in ("draft", "open"):
        t.status = "live"
        t.save(update_fields=["status"])
    return f


def score_ball(f, runs=0, wicket=0, legal=1, side=None):
    """Cricket: runs/wicket/legal ball for the batting side. Points sports: pass side + runs (points)."""
    if f.state != "live":
        raise ValidationError({"fixture": "Start the match first."})
    t = f.tournament
    if t.sport.scoring == "cricket":
        if cricket_result(f):
            raise ValidationError({"fixture": "Innings complete. Confirm or undo."})
        bat = batting_side(f)
        _add(f, bat, "runs", runs)
        _add(f, bat, "wkts", wicket)
        _add(f, bat, "balls", legal)
        event = [bat, runs, wicket, legal, 0]
        if f.innings == 1 and (_get(f, bat, "wkts") >= max_wickets(t) or _get(f, bat, "balls") >= t.overs * 6):
            f.innings = 2
            event[4] = 1
        f.history = f.history + [event]
    else:
        if side not in ("a", "b"):
            raise ValidationError({"side": "Pick which team scored."})
        _add(f, side, "runs", runs or 1)
        f.history = f.history + [[side, runs or 1, 0, 0, 0]]
    f.save()
    return f


def end_innings(f):
    if f.tournament.sport.scoring != "cricket" or f.innings != 1:
        raise ValidationError({"fixture": "Nothing to end."})
    f.innings = 2
    f.history = f.history + [[batting_side(f), 0, 0, 0, 1]]
    f.save()
    return f


def undo(f):
    if f.state == "done":
        raise ValidationError({"fixture": "Result already confirmed."})
    if not f.history:
        raise ValidationError({"fixture": "Nothing to undo."})
    side, r, w, b, switched = f.history[-1]
    _add(f, side, "runs", -r)
    _add(f, side, "wkts", -w)
    _add(f, side, "balls", -b)
    if switched:
        f.innings = 1
    f.history = f.history[:-1]
    f.save()
    return f


def pending_result(f):
    return cricket_result(f) if f.tournament.sport.scoring == "cricket" else points_result(f)


@transaction.atomic
def confirm_result(f, winner_side=None):
    res = pending_result(f)
    side = winner_side or (res["side"] if res else None)
    if side not in ("a", "b"):
        raise ValidationError({"fixture": "Pick a winner (scores are level or the match is not finished)."})
    winner = f.team_a if side == "a" else f.team_b
    loser = f.team_b if side == "a" else f.team_a
    f.winner = winner
    f.result_text = res["text"] if res and res["side"] == side else f"{winner.name} won"
    f.state = "done"
    f.save()
    t = f.tournament
    if f.stage == "ko" and loser:
        loser.eliminated = True
        loser.save(update_fields=["eliminated"])
    if f.next_fixture_id:
        nf = Fixture.objects.select_for_update().get(pk=f.next_fixture_id)
        setattr(nf, f"team_{f.next_slot}", winner)
        if nf.team_a and nf.team_b:
            nf.state = "next"
        nf.save()
    if f.stage == "group" and not t.fixtures.filter(stage="group").exclude(state="done").exists():
        _fill_knockouts_from_groups(t)
    if not t.fixtures.exclude(state="done").exists():
        t.status = "completed"
        t.save(update_fields=["status"])
        champion = winner if f.stage == "ko" else standings(t)[0]["team"]
        notify(t.host, f"{t.name} finished", f"Champions: {champion.name}", "tournament")
    return f


def standings(t, group_label=None):
    teams = t.teams.all()
    if group_label:
        teams = teams.filter(group_label=group_label)
    table = {tm.id: {"team": tm, "played": 0, "won": 0, "lost": 0, "points": 0, "diff": 0} for tm in teams}
    qs = t.fixtures.filter(state="done").exclude(stage="ko")
    if group_label:
        qs = qs.filter(group_label=group_label)
    for f in qs:
        for side, team, other in (("a", f.team_a, "b"), ("b", f.team_b, "a")):
            if team and team.id in table:
                row = table[team.id]
                row["played"] += 1
                row["diff"] += _get(f, side, "runs") - _get(f, other, "runs")
                if f.winner_id == team.id:
                    row["won"] += 1
                    row["points"] += 2
                else:
                    row["lost"] += 1
    return sorted(table.values(), key=lambda r: (-r["points"], -r["diff"], r["team"].seed))


def _fill_knockouts_from_groups(t):
    for f in t.fixtures.filter(stage="ko", round_index=1):
        changed = False
        for slot in ("a", "b"):
            m = QUALIFIER_RE.match(getattr(f, f"placeholder_{slot}") or "")
            if m:
                table = standings(t, m.group(1))
                pos = int(m.group(2)) - 1
                if pos < len(table):
                    setattr(f, f"team_{slot}", table[pos]["team"])
                    changed = True
        if changed:
            f.state = "next" if f.team_a and f.team_b else "tbd"
            f.save()
    for tm in t.teams.all():
        in_ko = t.fixtures.filter(stage="ko").filter(team_a=tm).exists() or t.fixtures.filter(stage="ko", team_b=tm).exists()
        if not in_ko:
            tm.eliminated = True
            tm.save(update_fields=["eliminated"])


def team_status(team):
    t = team.tournament
    if t.status in ("draft", "open") and not t.fixtures.exists():
        return "Registered"
    if team.eliminated:
        last = t.fixtures.filter(state="done").filter(
            models_q_team(team)).order_by("-round_index").first()
        return f"Out in {short_round(last.round_name)}" if last else "Out"
    live = t.fixtures.filter(models_q_team(team)).exclude(state="done").order_by("round_index").first()
    if t.status == "completed":
        return "Champions"
    if live:
        return f"In {live.round_name.lower().rstrip('s')}" if live.stage == "ko" else live.round_name
    return "Playing"


def models_q_team(team):
    from django.db.models import Q
    return Q(team_a=team) | Q(team_b=team)


def short_round(name):
    return {"Quarter-finals": "QF", "Semi-finals": "SF", "Final": "final", "Round of 16": "R16"}.get(name, name)


def register_team(t, user, team_name):
    if t.status not in ("open",):
        raise ValidationError({"tournament": "Registrations are closed."})
    if t.teams.count() >= t.team_count:
        raise ValidationError({"tournament": "All spots are taken."})
    if t.teams.filter(captain=user).exists():
        raise ValidationError({"tournament": "You have already registered a team."})
    name = (team_name or "").strip() or f"{user.get_short_name()}'s XI"
    if t.teams.filter(name__iexact=name).exists():
        raise ValidationError({"team_name": "That team name is taken."})
    team = TournamentTeam.objects.create(tournament=t, name=name, captain=user, captain_name=user.name,
                                         paid=t.entry_fee == 0)
    notify(t.host, "New team registered", f"{team.name} joined {t.name}", "tournament")
    return team
