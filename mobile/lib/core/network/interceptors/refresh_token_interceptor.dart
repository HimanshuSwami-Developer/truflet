import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';

/// On a 401, swaps the refresh token for a new access token and replays the request.
///
/// - Concurrent 401s share one refresh call (the server rotates refresh tokens, so parallel refreshes
///   would race each other).
/// - The session is cleared only when the server rejects the refresh token itself (400/401).
///   Timeouts, no network or a 5xx keep the tokens, so a slow start never signs the player out.
class RefreshTokenInterceptor extends Interceptor {
  final Dio dio;
  final TokenStorage tokens;
  final String baseUrl;
  RefreshTokenInterceptor({required this.dio, required this.tokens, required this.baseUrl});

  static const _retried = 'retried';
  Future<bool>? _refreshing;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    if (err.response?.statusCode != 401 || tokens.refresh == null || opts.extra[_retried] == true) {
      return handler.next(err);
    }
    final sentWith = opts.headers['Authorization'];
    // another request already refreshed while this one was in flight → just replay it
    final alreadyFresh = tokens.access != null && sentWith != 'Bearer ${tokens.access}';
    final ok = alreadyFresh || await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null));
    if (!ok) return handler.next(err);
    try {
      opts.extra[_retried] = true;
      opts.headers['Authorization'] = 'Bearer ${tokens.access}';
      return handler.resolve(await dio.fetch(opts));
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    try {
      // A bare Dio so the refresh call itself never loops through these interceptors.
      final r = await Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
      )).post('/auth/refresh/', data: {'refresh': tokens.refresh});
      await tokens.save(r.data['access'], r.data['refresh'] ?? tokens.refresh);
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 401) await tokens.clear(); // refresh token expired / revoked
      return false;
    } catch (_) {
      return false;
    }
  }
}
