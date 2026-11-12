import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/squad_repository.dart';

class SquadState {
  /// Groups · Friends · Requests
  final int tab;
  final List<Json> groups, friends, requests, nearby;
  final bool loaded;
  const SquadState({
    this.tab = 0,
    this.groups = const [],
    this.friends = const [],
    this.requests = const [],
    this.nearby = const [],
    this.loaded = false,
  });

  SquadState copyWith({
    int? tab,
    List<Json>? groups,
    List<Json>? friends,
    List<Json>? requests,
    List<Json>? nearby,
    bool? loaded,
  }) => SquadState(
    tab: tab ?? this.tab,
    groups: groups ?? this.groups,
    friends: friends ?? this.friends,
    requests: requests ?? this.requests,
    nearby: nearby ?? this.nearby,
    loaded: loaded ?? this.loaded,
  );
}

/// 17 · Squad: my groups, friends, friend requests and players nearby.
class SquadCubit extends Cubit<SquadState> {
  final SquadRepository _repo;
  SquadCubit({required SquadRepository repository}) : _repo = repository, super(const SquadState());

  /// Returns an error message to show, or null.
  Future<String?> load() async {
    try {
      final r = await Future.wait([_repo.groups(), _repo.friends(), _repo.requests(), _repo.nearby()]);
      _emit(state.copyWith(groups: r[0], friends: r[1], requests: r[2], nearby: r[3], loaded: true));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void selectTab(int i) => _emit(state.copyWith(tab: i));

  /// Creates a group, shows the Groups tab and refreshes. Throws ApiError.
  Future<void> createGroup(String name, dynamic sportId) async {
    await _repo.createGroup(name: name, sportId: sportId);
    _emit(state.copyWith(tab: 0));
    load();
  }

  Future<void> acceptRequest(dynamic requestId) async {
    await _repo.acceptRequest(requestId);
    load();
  }

  Future<void> declineRequest(dynamic requestId) async {
    await _repo.declineRequest(requestId);
    load();
  }

  /// Sends a friend request to the k-th nearby player and flips their button to "Requested".
  Future<void> addFriend(int k) async {
    final r = await _repo.addFriend(state.nearby[k]['id']);
    final nearby = [...state.nearby];
    nearby[k] = {...nearby[k], 'requested': r['requested']};
    _emit(state.copyWith(nearby: nearby));
  }

  void _emit(SquadState s) {
    if (!isClosed) emit(s);
  }
}
