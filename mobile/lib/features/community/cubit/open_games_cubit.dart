import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/community_repository.dart';

/// Open games at one venue, and joining one.
class OpenGamesCubit extends DataCubit<List<Json>> {
  final CommunityRepository _repo;
  OpenGamesCubit({required int venueId, required CommunityRepository repository})
    : _repo = repository,
      super(() => repository.openGames(venueId));

  /// Pays my share and joins. Throws ApiError.
  Future<void> join(int gameId, {required String method, String upiId = ''}) async {
    await _repo.joinGame(gameId, method: method, upiId: upiId);
    await load();
  }
}
