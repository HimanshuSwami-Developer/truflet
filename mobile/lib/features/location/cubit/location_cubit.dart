import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/location_repository.dart';
import 'location_state.dart';

/// 3 · Choose location: city grid, area list, search and "use my location".
class LocationCubit extends Cubit<LocationState> {
  final LocationRepository _repo;
  final AppCubit _app;

  LocationCubit({required LocationRepository repository, required this._app}) : _repo = repository, super(const LocationState());

  /// Loads cities and preselects the player's current area when its city is live,
  /// otherwise the first area of the first live city.
  Future<void> load() async {
    try {
      final current = _app.state.areaId;
      final data = await _repo.cities();
      var ci = -1;
      for (var i = 0; i < data.length; i++) {
        if (LocationState.isLive(data[i]) && asList(data[i]['areas']).any((a) => a['id'] == current)) ci = i;
      }
      final keepCurrent = ci >= 0;
      if (!keepCurrent) ci = data.indexWhere(LocationState.isLive);
      if (ci < 0) ci = 0;
      final areas = data.isEmpty ? <Json>[] : asList(data[ci]['areas']);
      _emit(
        state.copyWith(
          cities: data,
          city: ci,
          areaId: keepCurrent ? current : (areas.isNotEmpty ? areas.first['id'] : null),
          error: null,
        ),
      );
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
    }
  }

  /// Finds the nearest area from GPS. Returns an error message to show, or null.
  Future<String?> useGps() async {
    _emit(state.copyWith(gpsBusy: true));
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw ApiError('Location permission is off. Pick your area below.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final r = await _repo.locate(pos.latitude, pos.longitude);
      final ci = state.cities.indexWhere((c) => c['id'] == r['city_id']);
      _emit(
        state.copyWith(
          city: ci >= 0 ? ci : null,
          areaId: r['area_id'],
          lat: pos.latitude,
          lng: pos.longitude,
          gpsLabel: 'Located: ${r['area']}, ${r['city']}',
        ),
      );
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _emit(state.copyWith(gpsBusy: false));
    }
  }

  void setQuery(String q) => _emit(state.copyWith(query: q));

  void selectCity(int i) {
    if (!LocationState.isLive(state.cities[i])) return;
    final a = asList(state.cities[i]['areas']);
    _emit(state.copyWith(city: i, areaId: a.isNotEmpty ? a.first['id'] : null, gpsLabel: null));
  }

  /// Picking a search result also switches to that area's city and clears the search.
  void selectArea(Json a) {
    if (a['_live'] == false) return;
    _emit(
      state.copyWith(
        areaId: a['id'],
        city: a['_city'] != null ? state.cities.indexWhere((c) => c['name'] == a['_city']) : null,
        query: '',
      ),
    );
  }

  /// Saves the chosen area for the session. Returns false when nothing is selected.
  Future<bool> confirm() async {
    final a = state.area;
    if (a == null || !LocationState.isLive(state.cities[state.city])) return false;
    await _app.setArea(
      id: a['id'],
      area: a['name'],
      city: state.cities[state.city]['name'],
      lat: state.lat ?? a['lat']?.toDouble(),
      lng: state.lng ?? a['lng']?.toDouble(),
    );
    return true;
  }

  void _emit(LocationState s) {
    if (!isClosed) emit(s);
  }
}
