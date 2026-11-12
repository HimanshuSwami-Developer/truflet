import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Matches, tournaments, fixtures and live scoring.
class PlayRepository {
  final ApiClient _api;
  PlayRepository(this._api);

  /// `{live, upcoming, hosting, past, open_tournaments}`.
  Future<Json> home() async => asMap(await _api.get('/play/home/'));

  Future<Json> tournament(int id) async => asMap(await _api.get('/play/tournaments/$id/'));

  /// [body] is `{team_name}` from the Play hub, `{}` from the tournament page.
  Future<dynamic> register(int tournamentId, Json body) => _api.post('/play/tournaments/$tournamentId/register/', body);

  Future<dynamic> unregister(int tournamentId) => _api.delete('/play/tournaments/$tournamentId/register/');

  Future<dynamic> addTeam(int tournamentId, {required String name, required String captainName}) =>
      _api.post('/play/tournaments/$tournamentId/teams/', {'name': name, 'captain_name': captainName});

  Future<dynamic> payEntry(int tournamentId, dynamic teamId) =>
      _api.post('/play/tournaments/$tournamentId/teams/$teamId/pay/', {'method': 'upi'});

  Future<dynamic> generateFixtures(int tournamentId) => _api.post('/play/tournaments/$tournamentId/generate/');

  Future<dynamic> remindUnpaid(int tournamentId) => _api.post('/play/tournaments/$tournamentId/remind/');

  Future<dynamic> startFixture(dynamic fixtureId) => _api.post('/play/fixtures/$fixtureId/start/');

  /// Live scoring: [action] is ball | undo | end-innings | confirm. Returns the updated fixture.
  Future<Json> scoreFixture(dynamic fixtureId, String action, Json body) async =>
      asMap(await _api.post('/play/fixtures/$fixtureId/$action/', body));

  /// Exact schedule & money for a tournament draft.
  Future<Json> plan(Json body) async => asMap(await _api.post('/play/plan/', body));

  Future<Json> createTournament(Json body) async => asMap(await _api.post('/play/tournaments/', body));

  Future<Json> createGame(Json body) async => asMap(await _api.post('/play/games/', body));
}
