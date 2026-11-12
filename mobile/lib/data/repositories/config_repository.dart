import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// App-wide settings (fees, support info, offer banner) and the sport catalogue.
class ConfigRepository {
  final ApiClient _api;
  ConfigRepository(this._api);

  Future<Json> config() async => asMap(await _api.get('/config/'));

  Future<List<Json>> sports() async => asList(await _api.get('/sports/'));
}
