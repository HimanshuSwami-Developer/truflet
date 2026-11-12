import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';

/// 10 · Ticket: the booking pass, cancellation quote and cancellation.
class TicketCubit extends DataCubit<Json> {
  final BookingRepository _repo;
  final int bookingId;

  TicketCubit({required this.bookingId, required BookingRepository repository})
    : _repo = repository,
      super(() => repository.details(bookingId));

  /// Back to the spinner and fetch again (after a cancel or reschedule).
  Future<void> reload() async {
    if (isClosed) return;
    emit(const DataState<Json>());
    await load();
  }

  Future<Json> cancelQuote() => _repo.cancelQuote(bookingId);

  Future<Json> cancel() => _repo.cancel(bookingId);
}
