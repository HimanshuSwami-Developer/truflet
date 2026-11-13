import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_error.dart';
import '../../core/network/json.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/storage/token_storage.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/repositories/user_repository.dart';
import 'app_state.dart';

/// Session, location, config, active tab and favourites — everything more than one screen needs.
class AppCubit extends Cubit<AppState> {
  final TokenStorage _tokens;
  final AppPreferences _prefs;
  final ConfigRepository _configRepo;
  final UserRepository _userRepo;

  AppCubit({
    required this._tokens,
    required this._prefs,
    required ConfigRepository configRepository,
    required UserRepository userRepository,
  }) : _configRepo = configRepository,
       _userRepo = userRepository,
       super(const AppState()) {
    // the session ended underneath us (e.g. refresh token expired) → show the signed-out state
    _tokens.onCleared = () {
      if (!isClosed && state.user != null) emit(state.copyWith(user: null, saved: const {}, tab: 0));
    };
  }

  /// Signed in = holds a token. The profile may still be loading (screens show a skeleton until it
  /// arrives); only the server rejecting the token (401 after a failed refresh) signs the player out.
  bool get loggedIn => _tokens.hasAccess;

  /// Keeps the cached profile in step with the session.
  @override
  void onChange(Change<AppState> change) {
    super.onChange(change);
    if (!identical(change.currentState.user, change.nextState.user)) _prefs.saveUser(change.nextState.user);
  }

  /// Restores the saved area and session, then loads config, sports and the profile.
  /// Network failures are swallowed so the app still opens offline.
  Future<void> boot() async {
    final saved = await _prefs.read();
    emit(
      state.copyWith(
        onboarded: saved.onboarded,
        areaId: saved.areaId,
        areaName: saved.areaName,
        cityName: saved.cityName,
        lat: saved.lat,
        lng: saved.lng,
      ),
    );
    await _tokens.load();
    if (_tokens.hasAccess) {
      // show the player signed in immediately; refreshMe below brings it up to date
      final cached = await _prefs.readUser();
      if (cached != null) emit(state.copyWith(user: cached));
    } else {
      await _prefs.saveUser(null);
    }
    await Future.wait([
      _quietly(() async => emit(state.copyWith(config: await _configRepo.config()))),
      _quietly(() async => emit(state.copyWith(sports: await _configRepo.sports()))),
      if (_tokens.hasAccess) _quietly(refreshMe),
    ]);
  }

  /// Reloads sports + config when the startup fetch failed (e.g. server was offline
  /// when the app launched). Throws [ApiError] if the server is still unreachable.
  Future<void> ensureBasics() async {
    if (state.sports.isNotEmpty && state.config.isNotEmpty) return;
    final r = await Future.wait([_configRepo.sports(), _configRepo.config()]);
    emit(state.copyWith(sports: r[0] as List<Json>, config: r[1] as Json));
  }

  Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// Network errors and server hiccups keep the session (and the cached profile) as is.
  Future<void> refreshMe() async {
    try {
      final me = await _userRepo.me();
      emit(state.copyWith(user: me));
    } on ApiError catch (e) {
      if (e.status == 401 && !_tokens.hasAccess) await logout();
    }
  }

  /// Stores the tokens from a successful code check. A first-time player inherits the area
  /// they picked during onboarding.
  Future<void> setLoggedIn(Json data) async {
    await _tokens.save(data['access'], data['refresh']);
    var user = asMap(data['user']);
    emit(state.copyWith(user: user));
    if (user['home_area'] == null && state.areaId != null) {
      try {
        user = await _userRepo.updateMe({'home_area_id': state.areaId, 'lat': ?state.lat, 'lng': ?state.lng});
      } catch (_) {}
    }
    emit(state.copyWith(user: user));
  }

  void setUser(Json u) => emit(state.copyWith(user: u));

  Future<void> updateMe(Json patch) async {
    final u = await _userRepo.updateMe(patch);
    emit(state.copyWith(user: u));
  }

  Future<void> logout() async {
    await _tokens.clear();
    emit(state.copyWith(user: null, saved: const {}, tab: 0));
  }

  Future<void> finishOnboarding() async {
    emit(state.copyWith(onboarded: true));
    await _prefs.setOnboarded();
  }

  Future<void> setArea({required int id, required String area, required String city, double? lat, double? lng}) async {
    emit(state.copyWith(areaId: id, areaName: area, cityName: city, lat: lat, lng: lng));
    await _prefs.saveArea(id: id, area: area, city: city, lat: lat, lng: lng);
    if (loggedIn) {
      try {
        await updateMe({'home_area_id': id, 'lat': ?lat, 'lng': ?lng});
      } catch (_) {}
    }
  }

  void setTab(int i) => emit(state.copyWith(tab: i));

  // ---------------------------------------------------------------- favourites

  void replaceSaved(Iterable<int> ids) => emit(state.copyWith(saved: {...ids}));

  void markSaved(int venueId, bool saved) =>
      emit(state.copyWith(saved: saved ? {...state.saved, venueId} : ({...state.saved}..remove(venueId))));
}
