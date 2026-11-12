import '../../../core/network/json.dart';

class LocationState {
  final List<Json> cities;
  final int city;
  final int? areaId;
  final String query;
  final bool gpsBusy;
  final String? gpsLabel;
  final double? lat, lng;
  final String? error;

  /// Cities have arrived from the server at least once.
  final bool loaded;

  const LocationState({
    this.cities = const [],
    this.city = 0,
    this.areaId,
    this.query = '',
    this.gpsBusy = false,
    this.gpsLabel,
    this.lat,
    this.lng,
    this.error,
    this.loaded = false,
  });

  /// First load still in flight (show the skeleton).
  bool get loading => !loaded && error == null;

  /// Only live cities can be picked; the rest show as "Coming soon". Older servers don't send the flag → live.
  static bool isLive(Json c) => c['is_live'] != false;

  List<Json> get areas => cities.isEmpty ? [] : asList(cities[city]['areas']);
  Json? get area => areas.where((a) => a['id'] == areaId).firstOrNull;

  /// Areas of the selected city, or — while searching — matches across every city
  /// (tagged with `_city`, and `_live` = whether that city can be picked).
  List<Json> get filteredAreas => query.isEmpty
      ? areas
      : cities
            .expand((c) => asList(c['areas']).map((a) => {...a, '_city': c['name'], '_live': isLive(c)}))
            .where((a) => '${a['name']} ${a['pincode']} ${a['_city']}'.toLowerCase().contains(query.toLowerCase()))
            .toList();

  static const _keep = Object();

  LocationState copyWith({
    List<Json>? cities,
    int? city,
    Object? areaId = _keep,
    String? query,
    bool? gpsBusy,
    Object? gpsLabel = _keep,
    Object? lat = _keep,
    Object? lng = _keep,
    Object? error = _keep,
    bool? loaded,
  }) => LocationState(
    cities: cities ?? this.cities,
    city: city ?? this.city,
    areaId: identical(areaId, _keep) ? this.areaId : areaId as int?,
    query: query ?? this.query,
    gpsBusy: gpsBusy ?? this.gpsBusy,
    gpsLabel: identical(gpsLabel, _keep) ? this.gpsLabel : gpsLabel as String?,
    lat: identical(lat, _keep) ? this.lat : lat as double?,
    lng: identical(lng, _keep) ? this.lng : lng as double?,
    error: identical(error, _keep) ? this.error : error as String?,
    loaded: loaded ?? this.loaded,
  );
}
