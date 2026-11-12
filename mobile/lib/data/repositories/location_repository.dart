import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Cities, their areas, and reverse lookup from GPS.
class LocationRepository {
  final ApiClient _api;
  LocationRepository(this._api);

  Future<List<Json>> cities() async => asList(await _api.get('/cities/'));

  /// Nearest area for a GPS fix: `{city_id, city, area_id, area}`.
  Future<Json> locate(double lat, double lng) async => asMap(await _api.get('/locate/', {'lat': lat, 'lng': lng}));
}
