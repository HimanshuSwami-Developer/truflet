import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import 'slot_booking_state.dart';

/// 6 · Slot picker: sport · date · court · duration · start time. Also reschedules a booking.
class SlotBookingCubit extends Cubit<SlotBookingState> {
  final VenueRepository _venues;
  final BookingRepository _bookings;

  SlotBookingCubit({required SlotBookingArgs args, required this._venues, required this._bookings}) : super(_initial(args));

  static SlotBookingState _initial(SlotBookingArgs a) {
    final today = DateTime.now();
    final sports = asList(a.venue['venue_sports']);
    final rs = a.reschedule;
    final wanted = rs != null ? rs['sport']['id'] : a.initialSportId;
    var s = SlotBookingState(
      venue: a.venue,
      reschedule: rs,
      today: today,
      sportIdx: sports.isEmpty ? 0 : sports.indexWhere((s) => s['sport_id'] == wanted).clamp(0, sports.length - 1),
      group: a.group,
      openGame: a.openGame,
    );
    if (a.openGame) s = s.copyWith(openPlayers: s.maxPlayers);
    if (a.initialDate != null) {
      final base = DateTime(today.year, today.month, today.day);
      s = s.copyWith(day: a.initialDate!.difference(base).inDays.clamp(0, 13));
    }
    s = s.copyWith(start: a.initialStart);
    if (a.initialStart != null) s = s.copyWith(dur: 1);
    if (rs != null) {
      s = s.copyWith(dur: rs['duration']);
      s = s.copyWith(courtIdx: s.courts.indexWhere((c) => c['id'] == rs['court']['id']).clamp(0, 99));
    }
    return s;
  }

  String get _day => DateFormat('yyyy-MM-dd').format(state.date);

  /// Loads the slot grid. Returns an error message to show, or null.
  Future<String?> load() async {
    if (state.sports.isEmpty || state.court == null) {
      _emit(state.copyWith(loading: false));
      return null;
    }
    _emit(state.copyWith(loading: true));
    try {
      final r = await _venues.availability(
        state.venue['id'],
        date: _day,
        sportId: state.sport['sport_id'],
        courtId: state.court!['id'],
      );
      final s = asList(r['slots']);
      var start = state.start;
      // keep the chosen start if possible, otherwise preselect the first evening slot that fits
      if (start == null || !s.any((x) => x['hour'] == start)) {
        final free = s.where((x) => x['status'] == 'free').map((x) => x['hour'] as int).toList();
        start = free.firstWhere((h) => h >= 18, orElse: () => free.isEmpty ? (s.isEmpty ? 18 : s.first['hour']) : free.first);
      }
      _emit(state.copyWith(slots: s, loading: false, start: start));
      return null;
    } catch (e) {
      _emit(state.copyWith(loading: false));
      return e.toString();
    }
  }

  void selectSport(int i) {
    final next = state.copyWith(sportIdx: i, courtIdx: 0);
    _emit(state.openGame ? next.copyWith(openPlayers: next.maxPlayers) : next);
  }

  void selectDay(int i) => _emit(state.copyWith(day: i));
  void selectCourt(int i) => _emit(state.copyWith(courtIdx: i));
  void setDuration(int n) => _emit(state.copyWith(dur: n));
  void pickStart(int h) => _emit(state.copyWith(start: h));
  void setBusy(bool v) => _emit(state.copyWith(busy: v));

  /// Moves an existing booking to the chosen slot.
  Future<void> reschedule() =>
      _bookings.reschedule(state.reschedule!['id'], date: _day, startHour: state.start, courtId: state.court!['id']);

  /// Holds the chosen slot and returns the unpaid booking for the payment screen.
  Future<Json> hold() => _bookings.hold({
    'venue': state.venue['id'],
    'court': state.court!['id'],
    'sport': state.sport['sport_id'],
    'date': _day,
    'start_hour': state.start,
    'duration': state.dur,
    if (state.group != null) 'group': state.group!['id'],
    if (state.openGame) 'open_players': state.openPlayers,
  });

  /// Total players for an open game (2 … the sport's max).
  void setOpenPlayers(int n) => _emit(state.copyWith(openPlayers: n.clamp(2, state.maxPlayers)));

  void _emit(SlotBookingState s) {
    if (!isClosed) emit(s);
  }
}
