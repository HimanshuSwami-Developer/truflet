import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/community_repository.dart';

/// The player's groups (Profile card and the "Play with a group" picker).
class GroupsCubit extends DataCubit<List<Json>> {
  final CommunityRepository _repo;
  GroupsCubit({required CommunityRepository repository}) : _repo = repository, super(repository.groups);

  /// Creates a group (I'm admin) and refreshes. Returns it. Throws ApiError.
  Future<Json> create(String name) async {
    final g = await _repo.createGroup(name.trim());
    await load();
    return g;
  }

  /// Joins a friend's group by invite code and refreshes. Throws ApiError.
  Future<Json> join(String code) async {
    final g = await _repo.joinWithCode(code.trim());
    await load();
    return g;
  }
}
