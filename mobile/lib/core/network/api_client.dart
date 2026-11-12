import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_error.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/refresh_token_interceptor.dart';

/// Thin Dio wrapper used by every repository.
///
/// Interceptor chain: auth header → token refresh on 401 → error mapping → (logging).
/// Every call returns the decoded JSON body or throws [ApiError].
class ApiClient {
  final TokenStorage tokens;
  late final Dio _dio;

  ApiClient({required AppConfig config, required this.tokens}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.addAll([
      AuthInterceptor(tokens),
      RefreshTokenInterceptor(dio: _dio, tokens: tokens, baseUrl: config.apiBaseUrl),
      ErrorInterceptor(),
      if (config.logNetwork) LoggingInterceptor(),
    ]);
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send(() => _dio.get(path, queryParameters: query));
  Future<dynamic> post(String path, [Object? body]) => _send(() => _dio.post(path, data: body ?? {}));
  Future<dynamic> patch(String path, Object body) => _send(() => _dio.patch(path, data: body));
  Future<dynamic> put(String path, Object body) => _send(() => _dio.put(path, data: body));
  Future<dynamic> delete(String path) => _send(() => _dio.delete(path));

  Future<dynamic> _send(Future<Response> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      final err = e.error;
      throw err is ApiError ? err : ApiError.fromDio(e);
    }
  }
}
