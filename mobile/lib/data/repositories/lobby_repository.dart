import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Matches (lobbies): discovery, Squad Builder, solo requests + screening thread, Match Room chat,
/// split checkout and host controls.
class LobbyRepository {
  final ApiClient _api;
  LobbyRepository(this._api);

  // ------------------------------------------------------------ discovery
  /// Public lobbies with open spots in the city of [areaId].
  Future<List<Json>> cityLobbies(int areaId, {int? sportId}) async =>
      asList(await _api.get('/lobbies/', {'area': areaId, 'sport': ?sportId}));

  /// Open lobbies at a venue, or only those covering one slot when [date] + [startHour] are given.
  Future<List<Json>> venueLobbies(int venueId, {String? date, int? startHour, int? courtId, int? sportId}) async =>
      asList(
        await _api.get('/venues/$venueId/lobbies/', {
          'date': ?date,
          'start_hour': ?startHour,
          'court': ?courtId,
          'sport': ?sportId,
        }),
      );

  /// Matches tab: `{upcoming, requests, past}`.
  Future<Json> mine() async => asMap(await _api.get('/lobbies/mine/'));

  // ------------------------------------------------------------ squad builder
  /// Recent co-players: `{recent: [...]}`.
  Future<Json> recentPlayers() async => asMap(await _api.get('/lobbies/players/'));

  /// Finds a Turflet player by email / mobile / referral code: `{player}`. Throws ApiError when not found.
  Future<Json> lookup(String contact) async => asMap(await _api.get('/lobbies/players/', {'contact': contact}));

  /// Creates the lobby. When the host pays upfront the response carries `checkout_booking` (a held slot).
  Future<Json> create(Json body) async => asMap(await _api.post('/lobbies/', body));

  // ------------------------------------------------------------ one lobby
  Future<Json> lobby(int id) async => asMap(await _api.get('/lobbies/$id/'));

  /// Opens a 1-on-1 screening thread with the host. Returns the request.
  Future<Json> requestToJoin(int id, String message) async =>
      asMap(await _api.post('/lobbies/$id/request/', {'message': message}));

  /// Match Room chat. [after] = last message id already shown.
  Future<List<Json>> messages(int id, {int? after}) async =>
      asList(await _api.get('/lobbies/$id/messages/', {'after': ?after}));

  Future<Json> send(int id, String body) async => asMap(await _api.post('/lobbies/$id/messages/', {'body': body}));

  /// Host: every request with the player's attendance stats.
  Future<List<Json>> requests(int id) async => asList(await _api.get('/lobbies/$id/requests/'));

  Future<Json> request(int id, int requestId) async => asMap(await _api.get('/lobbies/$id/requests/$requestId/'));

  Future<List<Json>> threadMessages(int id, int requestId, {int? after}) async =>
      asList(await _api.get('/lobbies/$id/requests/$requestId/messages/', {'after': ?after}));

  Future<Json> sendThread(int id, int requestId, String body) async =>
      asMap(await _api.post('/lobbies/$id/requests/$requestId/messages/', {'body': body}));

  /// [action] is approve | decline | withdraw.
  Future<Json> decide(int id, int requestId, String action) async =>
      asMap(await _api.post('/lobbies/$id/requests/$requestId/$action/'));

  // ------------------------------------------------------------ money
  /// Split checkout breakdown for my pending share.
  Future<Json> checkout(int id) async => asMap(await _api.get('/lobbies/$id/pay/'));

  Future<Json> pay(int id, {required String method, String upiId = ''}) async =>
      asMap(await _api.post('/lobbies/$id/pay/', {'method': method, 'upi_id': upiId}));

  /// pay-balance | switch-slot | unpublish | cancel | leave | checkin | report. Returns the lobby + `message`.
  Future<Json> action(int id, String action, [Json body = const {}]) async =>
      asMap(await _api.post('/lobbies/$id/$action/', body));

  Future<Json> removeMember(int id, int memberId) async => asMap(await _api.post('/lobbies/$id/members/$memberId/remove/'));
}
