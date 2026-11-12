import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../data/repositories/auth_repository.dart';
import 'login_state.dart';

/// Email → 6-digit code → (first time only) profile details.
class LoginCubit extends Cubit<LoginState> {
  final AuthRepository _repo;
  final AppCubit _app;

  LoginCubit({required AuthRepository repository, required this._app}) : _repo = repository, super(const LoginState());

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Emails a code. Returns the dev-mode code (to pre-fill) when the server sends one.
  Future<String?> sendCode(String email) async {
    if (!_emailPattern.hasMatch(email)) {
      _emit(state.copyWith(error: 'Enter a valid email address.'));
      return null;
    }
    _emit(state.copyWith(busy: true, error: null));
    try {
      final r = await _repo.requestCode(email);
      final dev = r['dev_code'] as String?;
      _emit(state.copyWith(step: LoginStep.code, devCode: dev));
      return dev;
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
      return null;
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  /// Checks the code and signs in. Returns true when the screen can close
  /// (existing player); new players move on to the profile step instead.
  Future<bool> verifyCode(String email, String code) async {
    _emit(state.copyWith(busy: true, error: null));
    try {
      final r = await _repo.verifyCode(email, code);
      await _app.setLoggedIn(r);
      if (r['is_new'] == true) {
        _emit(state.copyWith(step: LoginStep.profile));
        return false;
      }
      return true;
    } catch (e) {
      _emit(state.copyWith(error: e.toString()));
      return false;
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  void backToEmail({bool clearError = false}) =>
      _emit(clearError ? state.copyWith(step: LoginStep.email, error: null) : state.copyWith(step: LoginStep.email));

  void _emit(LoginState s) {
    if (!isClosed) emit(s);
  }
}
