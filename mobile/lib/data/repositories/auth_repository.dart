import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Email + one-time-code sign-in.
class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  /// Returns `{email, sent, dev_code?}` — `dev_code` only in dev mode.
  Future<Json> requestCode(String email) async => asMap(await _api.post('/auth/otp/request/', {'email': email}));

  /// Returns `{access, refresh, is_new, user}`.
  Future<Json> verifyCode(String email, String code) async =>
      asMap(await _api.post('/auth/otp/verify/', {'email': email, 'code': code}));
}
