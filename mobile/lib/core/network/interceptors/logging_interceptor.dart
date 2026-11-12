import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One line per request in the debug console (local & stage builds only).
/// Logs method, path, status and duration — never headers, tokens or bodies.
class LoggingInterceptor extends Interceptor {
  static const _startedAt = 'startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, '${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, '${err.response?.statusCode ?? err.type.name} ✗');
    handler.next(err);
  }

  void _log(RequestOptions o, String result) {
    final started = o.extra[_startedAt];
    final ms = started is DateTime ? ' ${DateTime.now().difference(started).inMilliseconds}ms' : '';
    debugPrint('[api] ${o.method} ${o.path} → $result$ms');
  }
}
