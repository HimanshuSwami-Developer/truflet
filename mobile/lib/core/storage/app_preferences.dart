import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local settings that survive restarts: onboarding flag, the chosen area and the last-seen profile.
class AppPreferences {
  static const _onboarded = 'onboarded';
  static const _areaId = 'areaId';
  static const _areaName = 'areaName';
  static const _cityName = 'cityName';
  static const _lat = 'lat';
  static const _lng = 'lng';
  static const _user = 'user';

  Future<SavedLocation> read() async {
    final p = await SharedPreferences.getInstance();
    return SavedLocation(
      onboarded: p.getBool(_onboarded) ?? false,
      areaId: p.getInt(_areaId),
      areaName: p.getString(_areaName) ?? '',
      cityName: p.getString(_cityName) ?? '',
      lat: p.getDouble(_lat),
      lng: p.getDouble(_lng),
    );
  }

  /// Last profile fetched from the server, so a restart shows the player signed in straight away
  /// even before (or without) the network answering.
  Future<Map<String, dynamic>?> readUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_user);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(Map<String, dynamic>? user) async {
    final p = await SharedPreferences.getInstance();
    user == null ? await p.remove(_user) : await p.setString(_user, jsonEncode(user));
  }

  Future<void> setOnboarded() async => (await SharedPreferences.getInstance()).setBool(_onboarded, true);

  Future<void> saveArea({required int id, required String area, required String city, double? lat, double? lng}) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_areaId, id);
    await p.setString(_areaName, area);
    await p.setString(_cityName, city);
    if (lat != null) await p.setDouble(_lat, lat);
    if (lng != null) await p.setDouble(_lng, lng);
  }
}

class SavedLocation {
  final bool onboarded;
  final int? areaId;
  final String areaName, cityName;
  final double? lat, lng;
  const SavedLocation({
    required this.onboarded,
    required this.areaId,
    required this.areaName,
    required this.cityName,
    required this.lat,
    required this.lng,
  });
}
