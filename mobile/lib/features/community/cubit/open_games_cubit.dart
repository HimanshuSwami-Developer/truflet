import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/community_repository.dart';

/// Open games at one venue (or across the city when [venueId] is null), and joining one.
class OpenGamesCubit extends DataCubit<List<Json>> {
  final CommunityRepository _repo;
  OpenGamesCubit({int? venueId, int? areaId, required CommunityRepository repository})
    : _repo = repository,
      super(
        () => venueId != null
            ? repository.openGames(venueId)
            : areaId != null
            ? repository.cityGames(areaId)
            : Future.value(<Json>[]),
      );

  /// Pays my share and joins. Throws ApiError.
  Future<void> join(int gameId, {required String method, String upiId = ''}) async {
    await _repo.joinGame(gameId, method: method, upiId: upiId);
    await load();
  }
}
