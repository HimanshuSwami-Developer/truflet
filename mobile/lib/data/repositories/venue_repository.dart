import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Turfs: search, details, favourites, slot availability and reviews.
class VenueRepository {
  final ApiClient _api;
  VenueRepository(this._api);

  /// [query] keys: area, sport, q, lat, lng, sort.
  Future<List<Json>> search(Map<String, dynamic> query) async => asList(await _api.get('/venues/', query));

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
