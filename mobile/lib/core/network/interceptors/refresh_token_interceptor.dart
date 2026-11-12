import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';

/// On a 401, swaps the refresh token for a new access token once and replays the request.
/// If the refresh fails the session is cleared and the original error continues.
class RefreshTokenInterceptor extends Interceptor {
  final Dio dio;
  final TokenStorage tokens;
  final String baseUrl;
  RefreshTokenInterceptor({required this.dio, required this.tokens, required this.baseUrl});

  static const _retried = 'retried';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && tokens.refresh != null && err.requestOptions.extra[_retried] != true) {
      try {
        // A bare Dio so the refresh call itself never loops through these interceptors.
        final r = await Dio(BaseOptions(baseUrl: baseUrl)).post('/auth/refresh/', data: {'refresh': tokens.refresh});
        await tokens.save(r.data['access'], r.data['refresh'] ?? tokens.refresh);
        final opts = err.requestOptions..extra[_retried] = true;
        opts.headers['Authorization'] = 'Bearer ${tokens.access}';
        return handler.resolve(await dio.fetch(opts));
      } catch (_) {
        await tokens.clear();
      }
    }
    handler.next(err);
  }
}
