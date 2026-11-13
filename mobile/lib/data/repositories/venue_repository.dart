import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Turfs: search, details, favourites, slot availability and reviews.
class VenueRepository {
  final ApiClient _api;
  VenueRepository(this._api);

  /// [query] keys: area, sport, q, lat, lng, sort, amenities, price_min, price_max, date, from_hour, to_hour.
  /// Returns `{items, radius_km, radius_label, notice}` — the radius widens 3 → 5 → 10 km → city-wide.
  Future<Json> search(Map<String, dynamic> query) async => asMap(await _api.get('/venues/', query));

  /// Amenity catalogue for the filter sheet: `[{name, icon}]`.
  Future<List<Json>> amenities() async => asList(await _api.get('/amenities/'));

  Future<Json> details(int venueId) async => asMap(await _api.get('/venues/$venueId/'));

  /// Toggles the favourite; returns `{is_saved}`.
  Future<Json> toggleSaved(int venueId) async => asMap(await _api.post('/venues/$venueId/save/'));

  Future<List<Json>> saved({double? lat, double? lng}) async =>
      asList(await _api.get('/venues/saved/', {'lat': ?lat, 'lng': ?lng}));

  /// Hourly slots for one court on one day: `{slots: [...]}`.
  Future<Json> availability(int venueId, {required String date, required dynamic sportId, required dynamic courtId}) async =>
      asMap(await _api.get('/venues/$venueId/availability/', {'date': date, 'sport': sportId, 'court': courtId}));

  Future<void> review(int venueId, {required int rating, required dynamic bookingId}) =>
      _api.post('/venues/$venueId/review/', {'rating': rating, 'booking': bookingId});
}
