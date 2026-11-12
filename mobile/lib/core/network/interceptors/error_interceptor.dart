import 'package:dio/dio.dart';

import '../api_error.dart';

/// Attaches a user-facing [ApiError] to every failed request, so callers only deal with one error type.
/// Runs after [RefreshTokenInterceptor], i.e. only for errors that could not be recovered.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.error is ApiError ? err : err.copyWith(error: ApiError.fromDio(err)));
  }
}
