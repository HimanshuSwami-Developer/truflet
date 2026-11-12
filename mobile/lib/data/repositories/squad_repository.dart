import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Groups, friends, friend requests and players nearby.
class SquadRepository {
  final ApiClient _api;
  SquadRepository(this._api);

  Future<List<Json>> groups() async => asList(await _api.get('/squad/groups/'));
  Future<List<Json>> friends() async => asList(await _api.get('/squad/friends/'));
  Future<List<Json>> requests() async => asList(await _api.get('/squad/requests/'));
  Future<List<Json>> nearby() async => asList(await _api.get('/squad/nearby/'));

  Future<Json> group(int id) async => asMap(await _api.get('/squad/groups/$id/'));

  Future<void> createGroup({required String name, required dynamic sportId}) =>
      _api.post('/squad/groups/', {'name': name, 'sport_id': sportId});

  Future<void> acceptRequest(dynamic requestId) => _api.post('/squad/requests/$requestId/accept/');
  Future<void> declineRequest(dynamic requestId) => _api.post('/squad/requests/$requestId/decline/');

  /// Returns `{requested}`.
  Future<Json> addFriend(dynamic playerId) async => asMap(await _api.post('/squad/friends/$playerId/add/'));

  Future<void> rsvp(dynamic gameId, String response) => _api.post('/squad/games/$gameId/rsvp/', {'response': response});
}
