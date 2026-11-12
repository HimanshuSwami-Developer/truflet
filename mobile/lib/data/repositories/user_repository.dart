import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// The signed-in player's profile.
class UserRepository {
  final ApiClient _api;
  UserRepository(this._api);

  Future<Json> me() async => asMap(await _api.get('/me/'));

  Future<Json> updateMe(Json patch) async => asMap(await _api.patch('/me/', patch));

  /// Replaces the player's sports; each item is `{sport_id, level}`.
  Future<Json> setSports(List<Json> sports) async => asMap(await _api.put('/me/sports/', sports));
}
