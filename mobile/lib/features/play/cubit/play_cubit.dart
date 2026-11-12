import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/play_repository.dart';

class PlayState {
  /// `{live, upcoming, hosting, past, open_tournaments}`; null until loaded.
  final Json? data;
  final String? error;

  /// Upcoming · Hosting · Past
  final int tab;
  const PlayState({this.data, this.error, this.tab = 0});
}

/// 14 · Play hub: my games, the live match I host, and open tournaments.
class PlayCubit extends Cubit<PlayState> {
  final PlayRepository _repo;
  PlayCubit({required PlayRepository repository}) : _repo = repository, super(const PlayState());

  Future<void> load() async {
    try {
      final r = await _repo.home();
      _emit(PlayState(data: r, tab: state.tab));
    } catch (e) {
      _emit(PlayState(data: state.data, error: e.toString(), tab: state.tab));
    }
  }

  void selectTab(int i) => _emit(PlayState(data: state.data, error: state.error, tab: i));

  /// Withdraws my team from an open tournament, then refreshes.
  Future<void> unregister(int tournamentId) async {
    await _repo.unregister(tournamentId);
    load();
  }

  /// Registers a team (I'm the captain), then refreshes. Throws ApiError.
  Future<void> register(int tournamentId, String teamName) async {
    await _repo.register(tournamentId, {'team_name': teamName});
    load();
  }

  void _emit(PlayState s) {
    if (!isClosed) emit(s);
  }
}
