import '../../../core/network/json.dart';
import '../../../core/utils/formatters.dart';

class SlotBookingState {
  final Json venue;
  final Json? reschedule;
  final DateTime today;
  final int sportIdx, day, courtIdx, dur;
  final int? start;
  final List<Json> slots;
  final bool loading, busy;

  const SlotBookingState({
    required this.venue,
    required this.reschedule,
    required this.today,
    required this.sportIdx,
    this.day = 0,
    this.courtIdx = 0,
    this.dur = 2,
    this.start,
    this.slots = const [],
    this.loading = true,
    this.busy = false,
  });

  /// Open lobbies (groups recruiting solo players) covering the picked start hour.
  int get lobbiesAtStart => start == null ? 0 : ((slotAt(start!)?['lobbies'] as int?) ?? 0);

  bool get isReschedule => reschedule != null;
  List<Json> get sports => asList(venue['venue_sports']);
  List<Json> get allCourts => asList(venue['courts']);
  Json get sport => sports[sportIdx];
  List<Json> get courts => allCourts.where((c) => (c['sport_ids'] as List).contains(sport['sport_id'])).toList();
  Json? get court => courts.isEmpty ? null : courts[courtIdx.clamp(0, courts.length - 1)];
  DateTime get date => DateTime(today.year, today.month, today.day).add(Duration(days: day));

  Json? slotAt(int h) => slots.where((s) => s['hour'] == h).firstOrNull;

  /// Whether [start] + [dur] fits in free slots before closing, and the price if it does.
  ({bool valid, int total, String error}) get check {
    if (start == null) return (valid: false, total: 0, error: 'Pick a start time.');
    var total = 0;
    final closes = venue['closes_at'] as int;
    for (var k = 0; k < dur; k++) {
      final h = start! + k;
      if (h >= closes) {
        return (
          valid: false,
          total: 0,
          error: 'Venue closes at ${fmtHour(closes)}. Pick an earlier start or a shorter duration.',
        );
      }
      final s = slotAt(h);
      if (s == null || s['status'] != 'free') {
        return (valid: false, total: 0, error: 'The ${fmtHour(h)} slot is not available. Pick another start time or duration.');
      }
      total += s['price'] as int;
    }
    return (valid: true, total: total, error: '');
  }

  static const _keep = Object();

  SlotBookingState copyWith({
    int? sportIdx,
    int? day,
    int? courtIdx,
    int? dur,
    Object? start = _keep,
    List<Json>? slots,
    bool? loading,
    bool? busy,
  }) => SlotBookingState(
    venue: venue,
    reschedule: reschedule,
    today: today,
    sportIdx: sportIdx ?? this.sportIdx,
    day: day ?? this.day,
    courtIdx: courtIdx ?? this.courtIdx,
    dur: dur ?? this.dur,
    start: identical(start, _keep) ? this.start : start as int?,
    slots: slots ?? this.slots,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
  );
}
