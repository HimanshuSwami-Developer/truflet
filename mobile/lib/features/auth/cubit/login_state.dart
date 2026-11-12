enum LoginStep { email, code, profile }

class LoginState {
  final LoginStep step;
  final bool busy;
  final String? error;

  /// Dev mode only: the server returns the code so it can be pre-filled.
  final String? devCode;

  const LoginState({this.step = LoginStep.email, this.busy = false, this.error, this.devCode});

  static const _keep = Object();

  LoginState copyWith({LoginStep? step, bool? busy, Object? error = _keep, Object? devCode = _keep}) => LoginState(
    step: step ?? this.step,
    busy: busy ?? this.busy,
    error: identical(error, _keep) ? this.error : error as String?,
    devCode: identical(devCode, _keep) ? this.devCode : devCode as String?,
  );
}
