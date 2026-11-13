import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  /// `{items, unread}`.
  Future<Json> list() async => asMap(await _api.get('/notifications/'));

  Future<void> markAllRead() => _api.post('/notifications/read/');

  /// FCM token for push notifications to the signed-in player (re-assigned if another player had it).
  Future<void> registerDevice(String token, {required String platform}) =>
      _api.post('/devices/', {'token': token, 'platform': platform});

  /// Stops pushes to this device. Works without a session, so it can run right after sign-out.
  Future<void> unregisterDevice(String token) => _api.post('/devices/remove/', {'token': token});
}
