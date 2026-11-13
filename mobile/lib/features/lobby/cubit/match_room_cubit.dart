import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/lobby_repository.dart';

class MatchRoomState {
  final Json? lobby;
  final String? error;
  final List<Json> messages;

  /// Host only: join requests (loaded with the Requests tab).
  final List<Json>? requests;
  const MatchRoomState({this.lobby, this.error, this.messages = const [], this.requests});

  bool get isHost => lobby?['my_role'] == 'host';

  /// Still inside the room (left / removed players only get the public card back).
  bool get inRoom => lobby?['members'] != null;

  MatchRoomState copyWith({Json? lobby, String? error, List<Json>? messages, List<Json>? requests}) => MatchRoomState(
    lobby: lobby ?? this.lobby,
    error: error,
    messages: messages ?? this.messages,
    requests: requests ?? this.requests,
  );
}

/// 5 + 6 · Match Room: pinned header, chat with payment cards, players, the host's Requests tab and
/// every match action. Polls while open so chat and payments feel live.
class MatchRoomCubit extends Cubit<MatchRoomState> {
  final LobbyRepository _repo;
  final int lobbyId;
  Timer? _poll;
  int _tick = 0;
  bool _busy = false; // a slow poll never overlaps the next one

  MatchRoomCubit({required this.lobbyId, required LobbyRepository repository})
    : _repo = repository,
      super(const MatchRoomState());

  Future<void> load() async {
    try {
      final lobby = await _repo.lobby(lobbyId);
      _emit(state.copyWith(lobby: lobby));
      if (lobby['members'] != null) {
        _emit(state.copyWith(messages: await _repo.messages(lobbyId)));
        if (lobby['my_role'] == 'host' && lobby['is_public'] == true) await loadRequests();
      }
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
    }
  }

  /// Every poll refreshes the lobby (members, paid count, status, alerts) and new chat; payment
  /// cards change state in place (paid / expired), so the full chat is re-read every few polls.
  Future<void> _refresh() async {
    if (isClosed || _busy) return;
    _busy = true;
    _tick++;
    try {
      final lobby = await _repo.lobby(lobbyId);
      if (lobby['members'] == null) {
        _emit(state.copyWith(lobby: lobby)); // outside the room (removed, invited, ended): card only
        return;
      }
      final last = state.messages.isEmpty ? null : state.messages.last['id'] as int;
      final full = last == null || _tick % 3 == 0;
      final msgs = full ? await _repo.messages(lobbyId) : [...state.messages, ...await _repo.messages(lobbyId, after: last)];
      _emit(state.copyWith(lobby: lobby, messages: msgs));
      if (lobby['my_role'] == 'host' && lobby['is_public'] == true) await loadRequests();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<void> reload() async {
    _tick = 0;
    await load();
  }

  Future<void> loadRequests() async {
    try {
      _emit(state.copyWith(requests: await _repo.requests(lobbyId)));
    } catch (_) {}
  }

  /// Returns an error message, or null when sent.
  Future<String?> send(String body) async {
    try {
      final m = await _repo.send(lobbyId, body);
      _emit(state.copyWith(messages: [...state.messages, m]));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Applies a lobby returned by a payment or action.
  Future<void> applied(Json lobby) async {
    _emit(state.copyWith(lobby: lobby));
    if (lobby['members'] != null) {
      try {
        _emit(state.copyWith(messages: await _repo.messages(lobbyId)));
      } catch (_) {}
    }
  }

  /// pay-balance | switch-slot | unpublish | cancel | leave | checkin | report. Returns the server's message.
  /// Throws ApiError.
  Future<String> action(String name, [Json body = const {}]) async {
    final r = await _repo.action(lobbyId, name, body);
    await applied(r);
    return r['message'] ?? 'Done';
  }

  Future<void> removeMember(int memberId) async => applied(await _repo.removeMember(lobbyId, memberId));

  void _emit(MatchRoomState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
