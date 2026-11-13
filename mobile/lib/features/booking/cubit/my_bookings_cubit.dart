import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/venue_repository.dart';

const bookingTabs = ['upcoming', 'completed', 'cancelled'];

class MyBookingsState {
  final int tab;

  /// `{items, counts}` for the current tab; null until loaded.
  final Json? data;
  final String? error;
  const MyBookingsState({this.tab = 0, this.data, this.error});
}

/// 9 · My bookings: upcoming / completed / cancelled, plus rating a finished game.
class MyBookingsCubit extends Cubit<MyBookingsState> {
  final BookingRepository _bookings;
  final VenueRepository _venues;

  MyBookingsCubit({required this._bookings, required this._venues}) : super(const MyBookingsState());

  Future<void> load() async {
    try {
      final r = await _bookings.list(bookingTabs[state.tab]);
      _emit(MyBookingsState(tab: state.tab, data: r));
    } catch (e) {
      _emit(MyBookingsState(tab: state.tab, data: state.data, error: e.toString()));
    }
  }

  /// Fresh fetch that shows the skeleton again (used when the player returns to the tab).
  Future<void> reload() async {
    _emit(MyBookingsState(tab: state.tab));
    await load();
  }

  void selectTab(int i) {
    _emit(MyBookingsState(tab: i, data: state.data, error: state.error));
    load();
  }

  /// Rates the venue for a completed booking, then refreshes. Throws ApiError on failure.
  Future<void> rate(Json b, int stars) async {
    await _venues.review(b['venue']['id'], rating: stars, bookingId: b['id']);
    load();
  }

  void _emit(MyBookingsState s) {
    if (!isClosed) emit(s);
  }
}
