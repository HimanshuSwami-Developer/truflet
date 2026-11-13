import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/lobby_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import 'explore_state.dart';

/// 1 · Home / Discovery: auto-expanding radius, sport pills, search, filter sheet (date & time window,
/// price, amenities), venue cards with live open-lobby counts, the city lobby board and the unread badge.
class ExploreCubit extends Cubit<ExploreState> {
  final VenueRepository _venues;
  final NotificationRepository _notifications;
  final LobbyRepository _lobbies;
  final AppCubit _app;
  Timer? _debounce;

  ExploreCubit({required this._venues, required this._notifications, required this._lobbies, required this._app})
    : super(const ExploreState());

  Future<void> load() async {
    final s = _app.state;
    final f = state.filters;
    final window = f.window == null ? null : timeWindows[f.window!];
    final day = f.dayOffset ?? (window != null ? 0 : null);
    try {
      await _app.ensureBasics();
      final r = await _venues.search({
        'area': ?s.areaId,
        'sport': ?state.sportId,
        if (state.q.isNotEmpty) 'q': state.q,
        'lat': ?s.lat,
        'lng': ?s.lng,
        'sort': state.sort,
        if (f.amenities.isNotEmpty) 'amenities': f.amenities.join(','),
        'price_min': ?f.priceMin,
        'price_max': ?f.priceMax,
        if (day != null) 'date': DateFormat('yyyy-MM-dd').format(DateTime.now().add(Duration(days: day))),
        'from_hour': ?window?.$2,
        'to_hour': ?window?.$3,
      });
      final data = asList(r['items']);
      _app.replaceSaved(data.where((v) => v['is_saved'] == true).map((v) => v['id'] as int));
      _emit(
        state.copyWith(
          venues: data,
          error: null,
          radiusLabel: r['radius_label'] ?? '',
          notice: r['notice'] ?? '',
        ),
      );
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
    }
    if (s.areaId != null) {
      try {
        _emit(state.copyWith(cityLobbies: await _lobbies.cityLobbies(s.areaId!, sportId: state.sportId)));
      } catch (_) {}
    }
    if (state.amenities.isEmpty) {
      try {
        _emit(state.copyWith(amenities: await _venues.amenities()));
      } catch (_) {}
    }
    if (_app.loggedIn) {
      try {
        final n = await _notifications.list();
        _emit(state.copyWith(unread: n['unread'] ?? 0));
      } catch (_) {}
    }
  }

  void selectSport(int? id) {
    _emit(state.copyWith(sportId: id));
    load();
  }

  /// Sort chosen in the filter sheet; results reload when the sheet's button is tapped.
  void setSort(String sort) => _emit(state.copyWith(sort: sort));

  /// Filters chosen in the sheet; results reload when the sheet's button is tapped.
  void setFilters(ExploreFilters f) => _emit(state.copyWith(filters: f));

  void clearFilters() {
    _emit(state.copyWith(filters: const ExploreFilters()));
    load();
  }

  /// The sort chip cycles Nearest → Lowest price → Top rated.
  void cycleSort() {
    _emit(state.copyWith(sort: exploreSortOrder[(exploreSortOrder.indexOf(state.sort) + 1) % 3]));
    load();
  }

  /// Debounced free-text search.
  void searchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _emit(state.copyWith(q: v.trim()));
      load();
    });
  }

  void clearUnread() => _emit(state.copyWith(unread: 0));

  /// Optimistically flips the heart, then trusts the server. Returns an error message, or null.
  Future<String?> toggleFavourite(Json v) async {
    final id = v['id'] as int;
    _app.markSaved(id, !_app.state.saved.contains(id));
    try {
      final r = await _venues.toggleSaved(id);
      _app.markSaved(id, r['is_saved'] == true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _emit(ExploreState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
