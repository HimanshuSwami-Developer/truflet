import 'dart:math' as math;

import '../../../core/network/json.dart';

const createFormats = [
  ('ko', 'Knockout', 'Lose once and you are out. Fastest to finish.'),
  ('league', 'League (round robin)', 'Everyone plays everyone. Most games per team.'),
  ('groups', 'Groups + knockout', 'Groups of 4, top 2 go to knockouts.'),
];
const createWindows = [
  ('morning', 'Morning', '7 AM – 1 PM', 6),
  ('full', 'Full day', '8 AM – 10 PM', 14),
  ('evening', 'Evening', '4 PM – 11 PM', 7),
];
const createMatchTimes = [18, 19, 20];

int matchCount(String f, int n) => f == 'ko'
    ? n - 1
    : f == 'league'
    ? n * (n - 1) ~/ 2
    : (n ~/ 4) * 6 + (n ~/ 2 - 1);

/// The next four weekend days (Sat/Sun), starting tomorrow.
List<DateTime> weekendDates() {
  final out = <DateTime>[];
  var d = DateTime.now().add(const Duration(days: 1));
  while (out.length < 4) {
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) out.add(DateTime(d.year, d.month, d.day));
    d = d.add(const Duration(days: 1));
  }
  return out;
}

/// Draft of a quick match or tournament across the 4 wizard steps.
class CreateState {
  /// 'match' | 'tour'
  final String type;
  final int step;
  final bool nameErr;
  final List<Json> sports;
  final int sportIdx;
  final String format;
  final int teams, perTeam, fee, groupIdx, venueIdx, dateIdx, timeIdx;
  final bool balance, busy;
  final List<Json> venues, groups;

  /// The created game / tournament, once published.
  final Json? done;

  /// Exact schedule & money from the server (tournaments).
  final Json? serverPlan;
  final String? loadError;
  final List<DateTime> dates;

  const CreateState({
    required this.type,
    required this.sports,
    required this.dates,
    this.step = 0,
    this.nameErr = false,
    this.sportIdx = 0,
    this.format = 'ko',
    this.teams = 8,
    this.perTeam = 8,
    this.fee = 2000,
    this.groupIdx = 0,
    this.venueIdx = 0,
    this.dateIdx = 0,
    this.timeIdx = 1,
    this.balance = true,
    this.busy = false,
    this.venues = const [],
    this.groups = const [],
    this.done,
    this.serverPlan,
    this.loadError,
  });

  bool get isTour => type == 'tour';
  Json get sport => sports[sportIdx.clamp(0, sports.length - 1)];
  Json? get venue => venues.isEmpty ? null : venues[venueIdx.clamp(0, venues.length - 1)];

  // planning maths mirrors the backend (play/services.plan); server numbers win when loaded
  ({int matches, int days, int perDay, int courts, int courtHours, int venueCost, int collected}) get plan {
    final sp = serverPlan;
    if (isTour && sp != null) {
      return (
        matches: sp['matches'] as int,
        days: sp['days'] as int,
        perDay: sp['per_day'] as int,
        courts: sp['courts'] as int,
        courtHours: sp['court_hours'] as int,
        venueCost: sp['venue_cost'] as int,
        collected: sp['collected'] as int,
      );
    }
    final matches = isTour ? matchCount(format, teams) : 1;
    final hpm = (sport['match_minutes'] as int) / 60;
    final win = createWindows[timeIdx].$4;
    const courts = 3;
    final perDay = (win / hpm).floor() * courts;
    final days = isTour ? math.max(1, (matches / math.max(1, perDay)).ceil()) : 1;
    final courtHours = isTour ? (matches * hpm).ceil() : 1;
    final price = (venue?['price_from'] ?? 0) as int;
    return (
      matches: matches,
      days: days,
      perDay: perDay,
      courts: courts,
      courtHours: courtHours,
      venueCost: courtHours * price,
      collected: fee * teams,
    );
  }

  static const _keep = Object();

  CreateState copyWith({
    String? type,
    int? step,
    bool? nameErr,
    List<Json>? sports,
    int? sportIdx,
    String? format,
    int? teams,
    int? perTeam,
    int? fee,
    int? groupIdx,
    int? venueIdx,
    int? dateIdx,
    int? timeIdx,
    bool? balance,
    bool? busy,
    List<Json>? venues,
    List<Json>? groups,
    Object? done = _keep,
    Object? serverPlan = _keep,
    Object? loadError = _keep,
  }) => CreateState(
    type: type ?? this.type,
    step: step ?? this.step,
    nameErr: nameErr ?? this.nameErr,
    sports: sports ?? this.sports,
    sportIdx: sportIdx ?? this.sportIdx,
    format: format ?? this.format,
    teams: teams ?? this.teams,
    perTeam: perTeam ?? this.perTeam,
    fee: fee ?? this.fee,
    groupIdx: groupIdx ?? this.groupIdx,
    venueIdx: venueIdx ?? this.venueIdx,
    dateIdx: dateIdx ?? this.dateIdx,
    timeIdx: timeIdx ?? this.timeIdx,
    balance: balance ?? this.balance,
    busy: busy ?? this.busy,
    venues: venues ?? this.venues,
    groups: groups ?? this.groups,
    done: identical(done, _keep) ? this.done : done as Json?,
    serverPlan: identical(serverPlan, _keep) ? this.serverPlan : serverPlan as Json?,
    loadError: identical(loadError, _keep) ? this.loadError : loadError as String?,
    dates: dates,
  );
}
