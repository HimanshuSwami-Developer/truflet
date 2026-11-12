import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/json.dart';
import '../../../data/repositories/squad_repository.dart';

/// 18 · Group: members, next game RSVP and invites. State is the group JSON (null until loaded).
class GroupCubit extends Cubit<Json?> {
  final SquadRepository _repo;
  final int id;

  GroupCubit({required this.id, required SquadRepository repository}) : _repo = repository, super(null);

  /// Returns an error message to show, or null.
  Future<String?> load() async {
    try {
      final r = await _repo.group(id);
      if (!isClosed) emit(r);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// in | maybe | out — shown immediately, then confirmed by a reload. Returns an error message, or null.
  Future<String?> rsvp(String response) async {
    final g = state!;
    final ng = asMap(g['next_game']);
    if (!isClosed) {
      emit({
        ...g,
        'next_game': {...ng, 'my_rsvp': response},
      });
    }
    try {
      await _repo.rsvp(ng['id'], response);
      return load();
    } catch (e) {
      return e.toString();
    }
  }
}
