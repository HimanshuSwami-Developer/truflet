import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// App-wide state: session, chosen location, config, sports and the active tab.
class AppState extends ChangeNotifier {
  Json? user;
  Json config = {};
  List<Json> sports = [];
  bool onboarded = false;
  int? areaId;
  String areaName = '';
  String cityName = '';
  double? lat, lng;
  int tab = 0;
  final Set<int> saved = {};

  bool get loggedIn => api.access != null && user != null;

  Future<void> boot() async {
    final p = await SharedPreferences.getInstance();
    onboarded = p.getBool('onboarded') ?? false;
    areaId = p.getInt('areaId');
    areaName = p.getString('areaName') ?? '';
    cityName = p.getString('cityName') ?? '';
    lat = p.getDouble('lat');
    lng = p.getDouble('lng');
    await api.loadTokens();
    await Future.wait([
      _safe(() async => config = asMap(await api.get('/config/'))),
      _safe(() async => sports = asList(await api.get('/sports/'))),
      if (api.access != null) _safe(refreshMe),
    ]);
    notifyListeners();
  }

  /// Reloads sports + config when the startup fetch failed (e.g. server was offline
  /// when the app launched). Throws ApiError if the server is still unreachable.
  Future<void> ensureBasics() async {
    if (sports.isNotEmpty && config.isNotEmpty) return;
    final r = await Future.wait([api.get('/sports/'), api.get('/config/')]);
    sports = asList(r[0]);
    config = asMap(r[1]);
    notifyListeners();
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  Future<void> refreshMe() async {
    try {
      user = asMap(await api.get('/me/'));
    } on ApiError catch (e) {
      if (e.status == 401) await logout();
    }
    notifyListeners();
  }

  Future<void> setLoggedIn(Json data) async {
    await api.saveTokens(data['access'], data['refresh']);
    user = asMap(data['user']);
    final home = user?['home_area'];
    if (home == null && areaId != null) {
      try {
        user = asMap(await api.patch('/me/', {'home_area_id': areaId, if (lat != null) 'lat': lat, if (lng != null) 'lng': lng}));
      } catch (_) {}
    }
    notifyListeners();
  }

  void setUser(Json u) {
    user = u;
    notifyListeners();
  }

  Future<void> updateMe(Json patch) async {
    user = asMap(await api.patch('/me/', patch));
    notifyListeners();
  }

  Future<void> logout() async {
    await api.clearTokens();
    user = null;
    saved.clear();
    tab = 0;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboarded = true;
    (await SharedPreferences.getInstance()).setBool('onboarded', true);
  }

  Future<void> setArea({required int id, required String area, required String city, double? lat, double? lng}) async {
    areaId = id;
    areaName = area;
    cityName = city;
    this.lat = lat;
    this.lng = lng;
    final p = await SharedPreferences.getInstance();
    await p.setInt('areaId', id);
    await p.setString('areaName', area);
    await p.setString('cityName', city);
    if (lat != null) await p.setDouble('lat', lat);
    if (lng != null) await p.setDouble('lng', lng);
    if (loggedIn) {
      try {
        await updateMe({'home_area_id': id, 'lat': ?lat, 'lng': ?lng});
      } catch (_) {}
    }
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  Json? sportByName(String name) => sports.where((s) => s['name'] == name).firstOrNull;
}
