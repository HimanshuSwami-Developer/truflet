import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/play_repository.dart';

class TournamentState {
  /// Full tournament (teams, rounds, money); null until loaded.
  final Json? data;
  final String? error;

  /// Fixtures · Teams & payments
  final int tab;

  /// A host / registration action is in flight.
  final bool busy;
  const TournamentState({this.data, this.error, this.tab = 0, this.busy = false});

  TournamentState copyWith({Json? data, String? error, int? tab, bool? busy}) =>
      TournamentState(data: data ?? this.data, error: error ?? this.error, tab: tab ?? this.tab, busy: busy ?? this.busy);
}

/// 16 · Tournament page. Hosts manage teams, fixtures and live scoring; players register and pay.
class TournamentCubit extends Cubit<TournamentState> {
  final PlayRepository _repo;
  final int id;

  TournamentCubit({required this.id, required PlayRepository repository}) : _repo = repository, super(const TournamentState());

  Future<void> load() async {
    try {
      final r = await _repo.tournament(id);
      _emit(TournamentState(data: r, tab: state.tab, busy: state.busy));
    } catch (e) {
      _emit(TournamentState(data: state.data, error: e.toString(), tab: state.tab, busy: state.busy));
    }
  }

  void selectTab(int i) => _emit(state.copyWith(tab: i));

  // ------------------------------------------------------------ actions (each returns an error message, or null)
  Future<String?> registerTeam() => _act(() => _repo.register(id, {}));
  Future<String?> payEntry(dynamic teamId) => _act(() => _repo.payEntry(id, teamId));
  Future<String?> addTeam(String name, String captain) => _act(() => _repo.addTeam(id, name: name, captainName: captain));
  Future<String?> generateFixtures() => _act(() => _repo.generateFixtures(id));
  Future<String?> remindUnpaid() => _act(() => _repo.remindUnpaid(id));
  Future<String?> startFixture(dynamic fixtureId) => _act(() => _repo.startFixture(fixtureId));

  /// One live-scoring step; returns the updated fixture. Throws ApiError.
  Future<Json> score(dynamic fixtureId, String action, Json body) => _repo.scoreFixture(fixtureId, action, body);

  /// Runs an action; uses the tournament it returns, or reloads.
  Future<String?> _act(Future<dynamic> Function() call) async {
    _emit(state.copyWith(busy: true));
    try {
      final r = await call();
      if (r is Map && r['rounds'] != null) {
        _emit(state.copyWith(data: asMap(r)));
      } else {
        await load();
      }
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  void _emit(TournamentState s) {
    if (!isClosed) emit(s);
  }
}
