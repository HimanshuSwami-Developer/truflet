import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/community_repository.dart';

/// 10 · Ticket: the booking pass, cancellation quote and cancellation.
/// Players who joined someone's open game can leave it from here.
class TicketCubit extends DataCubit<Json> {
  final BookingRepository _repo;
  final CommunityRepository _community;
  final int bookingId;

  TicketCubit({required this.bookingId, required BookingRepository repository, required this._community})
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

  /// Leaves an open game I joined (my share is refunded). Throws ApiError.
  Future<void> leaveGame(int gameId) => _community.leaveGame(gameId);
}
