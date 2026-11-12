import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

class NotificationRepository {
  final ApiClient _api;
  NotificationRepository(this._api);

  /// `{items, unread}`.
  Future<Json> list() async => asMap(await _api.get('/notifications/'));

  Future<void> markAllRead() => _api.post('/notifications/read/');
}
