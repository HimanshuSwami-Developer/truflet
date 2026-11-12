import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Groups (play with friends) and open games (play with strangers).
class CommunityRepository {
  final ApiClient _api;
  CommunityRepository(this._api);

  // ------------------------------------------------------------ groups
  /// My groups: `[{id, name, member_count, is_admin, initials}]`.
  Future<List<Json>> groups() async => asList(await _api.get('/groups/'));

  Future<Json> createGroup(String name) async => asMap(await _api.post('/groups/', {'name': name}));

  /// Members, invite code, pending invites and upcoming group games.
  Future<Json> group(int id) async => asMap(await _api.get('/groups/$id/'));

  /// [contact] is an email or a mobile number. Returns the group plus `{result: added|invited, message}`.
  Future<Json> addMember(int id, String contact) async => asMap(await _api.post('/groups/$id/members/', {'contact': contact}));

  Future<Json> removeMember(int id, int userId) async => asMap(await _api.post('/groups/$id/members/$userId/remove/'));

  Future<void> leaveGroup(int id) => _api.post('/groups/$id/leave/');

  Future<Json> joinWithCode(String code) async => asMap(await _api.post('/groups/join/', {'code': code}));

  // ------------------------------------------------------------ open games
  /// Upcoming games at a venue that strangers can join.
  Future<List<Json>> openGames(int venueId) async => asList(await _api.get('/venues/$venueId/open-games/'));

  Future<Json> joinGame(int gameId, {required String method, String upiId = ''}) async =>
      asMap(await _api.post('/open-games/$gameId/join/', {'method': method, 'upi_id': upiId}));

  Future<Json> leaveGame(int gameId) async => asMap(await _api.post('/open-games/$gameId/leave/'));
}
