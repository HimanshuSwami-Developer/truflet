import '../../core/network/json.dart';

/// Bottom-nav tabs, in order.
abstract final class AppTab {
  static const explore = 0;
  static const bookings = 1;
  static const profile = 2;
}

/// App-wide state shared by every screen: the signed-in player, server config, sport catalogue,
/// the chosen area, the active bottom-nav tab and the player's favourite venue ids.
class AppState {
  final Json? user;
  final Json config;
  final List<Json> sports;
  final bool onboarded;
  final int? areaId;
  final String areaName;
  final String cityName;
  final double? lat, lng;
  final int tab;
  final Set<int> saved;

  const AppState({
    this.user,
    this.config = const {},
    this.sports = const [],
    this.onboarded = false,
    this.areaId,
    this.areaName = '',
    this.cityName = '',
    this.lat,
    this.lng,
    this.tab = 0,
    this.saved = const {},
  });

  Json? sportByName(String name) => sports.where((s) => s['name'] == name).firstOrNull;

  static const _keep = Object();

  /// Nullable fields (user, areaId, lat, lng) can be cleared by passing null explicitly.
  AppState copyWith({
    Object? user = _keep,
    Json? config,
    List<Json>? sports,
    bool? onboarded,
    Object? areaId = _keep,
    String? areaName,
    String? cityName,
    Object? lat = _keep,
    Object? lng = _keep,
    int? tab,
    Set<int>? saved,
  }) => AppState(
    user: identical(user, _keep) ? this.user : user as Json?,
    config: config ?? this.config,
    sports: sports ?? this.sports,
    onboarded: onboarded ?? this.onboarded,
    areaId: identical(areaId, _keep) ? this.areaId : areaId as int?,
    areaName: areaName ?? this.areaName,
    cityName: cityName ?? this.cityName,
    lat: identical(lat, _keep) ? this.lat : lat as double?,
    lng: identical(lng, _keep) ? this.lng : lng as double?,
    tab: tab ?? this.tab,
    saved: saved ?? this.saved,
  );
}
