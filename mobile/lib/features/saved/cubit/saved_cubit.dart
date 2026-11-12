import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/venue_repository.dart';

class SavedState {
  /// null until loaded.
  final List<Json>? items;

  /// Removed this visit, so "Undo" can restore them.
  final List<Json> removed;
  const SavedState({this.items, this.removed = const []});
}

/// 11 · Saved venues with remove + undo.
class SavedCubit extends Cubit<SavedState> {
  final VenueRepository _repo;
  final AppCubit _app;

  SavedCubit({required VenueRepository repository, required this._app}) : _repo = repository, super(const SavedState());

  /// Returns an error message to show, or null.
  Future<String?> load() async {
    final s = _app.state;
    try {
      final r = await _repo.saved(lat: s.lat, lng: s.lng);
      _emit(SavedState(items: r, removed: state.removed));
      return null;
    } catch (e) {
      _emit(SavedState(items: const [], removed: state.removed));
      return e.toString();
    }
  }

  Future<void> remove(Json v) async {
    _emit(SavedState(items: [...?state.items]..remove(v), removed: [...state.removed, v]));
    _app.markSaved(v['id'], false);
    await _repo.toggleSaved(v['id']);
  }

  /// Re-saves everything removed this visit.
  Future<String?> undo() async {
    for (final v in state.removed) {
      await _repo.toggleSaved(v['id']);
      if (!isClosed) _app.markSaved(v['id'], true);
    }
    _emit(SavedState(items: state.items));
    return load();
  }

  void _emit(SavedState s) {
    if (!isClosed) emit(s);
  }
}
