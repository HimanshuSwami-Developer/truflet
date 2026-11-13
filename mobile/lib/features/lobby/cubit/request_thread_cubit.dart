import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/lobby_repository.dart';

class RequestThreadState {
  final Json? request;
  final List<Json> messages;
  final String? error;
  const RequestThreadState({this.request, this.messages = const [], this.error});

  bool get isHost => request?['is_host'] == true;
  String get status => request?['status'] ?? 'pending';
}

/// 5 · Request screening: the private 1-on-1 thread between a solo player and the host.
class RequestThreadCubit extends Cubit<RequestThreadState> {
  final LobbyRepository _repo;
  final int lobbyId, requestId;
  Timer? _poll;
  bool _busy = false; // a slow poll never overlaps the next one

  RequestThreadCubit({required this.lobbyId, required this.requestId, required LobbyRepository repository})
    : _repo = repository,
      super(const RequestThreadState());

  Future<void> load() async {
    try {
      final r = await _repo.request(lobbyId, requestId);
      final m = await _repo.threadMessages(lobbyId, requestId);
      _emit(RequestThreadState(request: r, messages: m));
      _poll ??= Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } catch (e) {
      _emit(RequestThreadState(request: state.request, messages: state.messages, error: e.toString()));
    }
  }

  /// Every poll re-reads the request too, so "Approved" / "Declined" shows up within seconds.
  Future<void> _refresh() async {
    if (isClosed || _busy) return;
    _busy = true;
    try {
      final last = state.messages.isEmpty ? null : state.messages.last['id'] as int;
      final fresh = await _repo.threadMessages(lobbyId, requestId, after: last);
      final req = await _repo.request(lobbyId, requestId);
      _emit(RequestThreadState(request: req, messages: [...state.messages, ...fresh]));
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  Future<String?> send(String body) async {
    try {
      final m = await _repo.sendThread(lobbyId, requestId, body);
      _emit(RequestThreadState(request: state.request, messages: [...state.messages, m]));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// approve | decline | withdraw. Throws ApiError.
  Future<void> decide(String action) async {
    final r = await _repo.decide(lobbyId, requestId, action);
    final m = await _repo.threadMessages(lobbyId, requestId);
    _emit(RequestThreadState(request: r, messages: m));
  }

  void _emit(RequestThreadState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
