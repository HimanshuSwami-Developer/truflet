import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/support_repository.dart';

class HelpState {
  final List<Json> faqs;
  final String q;

  /// Booking the player probably needs help with (passed in, or their next upcoming one).
  final Json? upcoming;
  const HelpState({this.faqs = const [], this.q = '', this.upcoming});
}

/// 12 · Help & support: FAQ search, contact, and a support ticket about a booking.
class HelpCubit extends Cubit<HelpState> {
  final SupportRepository _support;
  final BookingRepository _bookings;
  final AppCubit _app;

  HelpCubit({Json? booking, required this._support, required this._bookings, required this._app})
    : super(HelpState(upcoming: booking));

  Future<void> load() async {
    try {
      final f = await _support.faqs(state.q);
      _emit(HelpState(faqs: f, q: state.q, upcoming: state.upcoming));
    } catch (_) {}
    if (isClosed) return;
    if (state.upcoming == null && _app.loggedIn) {
      try {
        final items = asList((await _bookings.list('upcoming'))['items']);
        if (items.isNotEmpty) _emit(HelpState(faqs: state.faqs, q: state.q, upcoming: items.first));
      } catch (_) {}
    }
  }

  void search(String q) {
    _emit(HelpState(faqs: state.faqs, q: q, upcoming: state.upcoming));
    load();
  }

  /// Opens a support ticket (linked to [HelpState.upcoming] when there is one). Throws ApiError.
  Future<void> sendMessage(String message) {
    final b = state.upcoming;
    return _support.createTicket(
      subject: b != null ? 'Help with ${b['code']}' : 'Help request',
      message: message,
      bookingId: b?['id'],
    );
  }

  void _emit(HelpState s) {
    if (!isClosed) emit(s);
  }
}
