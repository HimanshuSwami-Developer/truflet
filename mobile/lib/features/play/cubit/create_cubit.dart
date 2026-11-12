import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/session/app_cubit.dart';
import '../../../data/repositories/play_repository.dart';
import '../../../data/repositories/squad_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import 'create_state.dart';

/// 15 · Create match / tournament wizard: basics → teams/players → venue & time → review.
class CreateCubit extends Cubit<CreateState> {
  final PlayRepository _play;
  final VenueRepository _venues;
  final SquadRepository _squad;
  final AppCubit _app;

  CreateCubit({required String type, required this._play, required this._venues, required this._squad, required AppCubit app})
    : _app = app,
      super(CreateState(type: type, sports: app.state.sports, dates: weekendDates()));

  static String defaultName(String type) => type == 'tour' ? 'Koramangala Premier League' : 'Sunday friendly';

  /// Makes sure sports are loaded (the server may have been down at launch), then loads venues.
  Future<void> init() async {
    _emit(state.copyWith(loadError: null));
    try {
      await _app.ensureBasics();
    } catch (e) {
      _emit(state.copyWith(loadError: e.toString()));
      return;
    }
    final sports = _app.state.sports;
    if (sports.isEmpty) {
      _emit(state.copyWith(sports: sports, loadError: 'No sports are set up yet. Add them in the admin panel.'));
      return;
    }
    _emit(state.copyWith(sports: sports));
    _emit(state.copyWith(perTeam: state.sport['team_size'] as int));
    loadVenues();
  }

  /// My groups, for "Invite from" on a quick match.
  Future<void> loadGroups() async {
    try {
      final g = await _squad.groups();
      _emit(state.copyWith(groups: g));
    } catch (_) {}
  }

  Future<void> loadVenues() async {
    if (state.sports.isEmpty) return;
    try {
      final v = await _venues.search({'area': ?_app.state.areaId, if (state.sports.isNotEmpty) 'sport': state.sport['id']});
      _emit(state.copyWith(venues: v, venueIdx: 0));
    } catch (_) {}
  }

  void setType(String t) => _emit(
    state.copyWith(
      type: t,
      perTeam: state.sports.isNotEmpty ? math.max(1, state.sport['team_size'] as int) : null,
      timeIdx: 1,
      nameErr: false,
    ),
  );

  /// Exact numbers from the backend (uses the venue's real courts and price).
  Future<void> fetchPlan() async {
    if (!state.isTour || state.venue == null) return;
    try {
      final r = await _play.plan({
        'sport_id': state.sport['id'],
        'venue_id': state.venue!['id'],
        'format': state.format,
        'teams': state.teams,
        'window': createWindows[state.timeIdx].$1,
        'entry_fee': state.fee,
      });
      _emit(state.copyWith(serverPlan: r));
    } catch (_) {}
  }

  /// Validates the step and moves on. Returns a message to toast, or null.
  String? next(String name) {
    if (state.step == 0 && name.trim().isEmpty) {
      _emit(state.copyWith(nameErr: true));
      return null;
    }
    if (state.step == 2 && state.venue == null) return 'Pick a venue';
    _emit(state.copyWith(step: state.step + 1, nameErr: false));
    if (state.step >= 2) fetchPlan();
    return null;
  }

  void back() => _emit(state.copyWith(step: state.step - 1));

  void clearNameError() => _emit(state.copyWith(nameErr: false));

  void selectSport(int i) {
    _emit(state.copyWith(sportIdx: i, perTeam: state.sports[i]['team_size']));
    loadVenues();
  }

  void setFormat(String f) => _emit(state.copyWith(format: f, teams: f == 'groups' && state.teams < 8 ? 8 : null));
  void setTeams(int n) => _emit(state.copyWith(teams: n));
  void setFee(int n) => _emit(state.copyWith(fee: n));
  void fewerPlayers() => _emit(state.copyWith(perTeam: math.max(1, state.perTeam - 1)));
  void morePlayers() => _emit(state.copyWith(perTeam: math.min(15, state.perTeam + 1)));
  void selectGroup(int i) => _emit(state.copyWith(groupIdx: i));
  void toggleBalance() => _emit(state.copyWith(balance: !state.balance));
  void selectDate(int i) => _emit(state.copyWith(dateIdx: i));

  void selectVenue(int i) {
    _emit(state.copyWith(venueIdx: i));
    fetchPlan();
  }

  void selectTime(int i) {
    _emit(state.copyWith(timeIdx: i));
    fetchPlan();
  }

  /// Creates the tournament / match. Returns an error message to toast, or null.
  Future<String?> publish(String name) async {
    _emit(state.copyWith(busy: true));
    final s = state;
    try {
      final date = DateFormat('yyyy-MM-dd').format(s.dates[s.dateIdx]);
      final done = s.isTour
          ? await _play.createTournament({
              'name': name.trim(),
              'sport_id': s.sport['id'],
              'venue_id': s.venue!['id'],
              'format': s.format,
              'teams': s.teams,
              'players_per_team': s.perTeam,
              'entry_fee': s.fee,
              'start_date': date,
              'window': createWindows[s.timeIdx].$1,
            })
          : await _play.createGame({
              'name': name.trim(),
              'sport_id': s.sport['id'],
              'venue_id': s.venue!['id'],
              'group_id': s.groupIdx < s.groups.length ? s.groups[s.groupIdx]['id'] : null,
              'per_side': s.perTeam,
              'auto_balance': s.balance,
              'date': date,
              'start_hour': createMatchTimes[s.timeIdx],
            });
      _emit(state.copyWith(done: done));
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  void _emit(CreateState s) {
    if (!isClosed) emit(s);
  }
}
