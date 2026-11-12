import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';

/// Adds `Authorization: Bearer <access>` to every request when the player is signed in.
class AuthInterceptor extends Interceptor {
  final TokenStorage tokens;
  AuthInterceptor(this.tokens);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (tokens.access != null) options.headers['Authorization'] = 'Bearer ${tokens.access}';
    handler.next(options);
  }
}
