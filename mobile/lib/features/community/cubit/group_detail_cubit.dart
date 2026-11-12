import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/community_repository.dart';

/// One group: members, invites, upcoming games.
class GroupDetailCubit extends DataCubit<Json> {
  final CommunityRepository _repo;
  final int id;
  GroupDetailCubit({required this.id, required CommunityRepository repository})
    : _repo = repository,
      super(() => repository.group(id));

  void _set(Json g) {
    if (!isClosed) emit(DataState<Json>(data: g));
  }

  /// Adds a player by email or mobile. Returns the server's message. Throws ApiError.
  Future<String> addMember(String contact) async {
    final g = await _repo.addMember(id, contact.trim());
    _set(g);
    return g['message'] ?? 'Done';
  }

  Future<void> removeMember(int userId) async => _set(await _repo.removeMember(id, userId));

  Future<void> leave() => _repo.leaveGroup(id);
}
