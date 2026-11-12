import 'package:shared_preferences/shared_preferences.dart';

/// JWT pair for the signed-in player, cached in memory and persisted in shared preferences.
class TokenStorage {
  static const _accessKey = 'access';
  static const _refreshKey = 'refresh';

  String? access;
  String? refresh;

  bool get hasAccess => access != null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    access = p.getString(_accessKey);
    refresh = p.getString(_refreshKey);
  }

  Future<void> save(String a, String r) async {
    access = a;
    refresh = r;
    final p = await SharedPreferences.getInstance();
    await p.setString(_accessKey, a);
    await p.setString(_refreshKey, r);
  }

  Future<void> clear() async {
    access = refresh = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_accessKey);
    await p.remove(_refreshKey);
  }
}
