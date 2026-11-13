import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/user_repository.dart';

/// 19 · Profile actions that are not plain session updates. Profile data itself lives in [AppCubit].
/// State = a tab-switch refresh is in flight (the screen shows its skeleton).
class ProfileCubit extends Cubit<bool> {
  final UserRepository _users;
  final AppCubit _app;

  ProfileCubit({required this._users, required this._app}) : super(false);

  Future<void> refresh() async {
    if (!isClosed) emit(true);
    await _app.refreshMe();
    if (!isClosed) emit(false);
  }

  /// Replaces the player's sports + levels. Returns an error message, or null.
  Future<String?> setSports(List<Json> sports) async {
    try {
      final r = await _users.setSports(sports.map((x) => {'sport_id': x['sport_id'], 'level': x['level']}).toList());
      _app.setUser(r);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
