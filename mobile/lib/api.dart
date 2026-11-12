import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;

/// Base URL of the Django API. Override with
///   flutter run --dart-define=API_BASE=https://api.yourdomain.com/api/v1
String get apiBase {
  const fromEnv = String.fromEnvironment('API_BASE');
  if (fromEnv.isNotEmpty) return fromEnv;
  return Platform.isAndroid ? 'http://10.0.2.2:8000/api/v1' : 'http://127.0.0.1:8000/api/v1';
}

class ApiError implements Exception {
  final String message;
  final int? status;
  ApiError(this.message, [this.status]);
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api I = Api._();

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: apiBase,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (access != null) o.headers['Authorization'] = 'Bearer $access';
        h.next(o);
      },
      onError: (e, h) async {
        // transparently refresh an expired access token once
        if (e.response?.statusCode == 401 && refresh != null && e.requestOptions.extra['retried'] != true) {
          try {
            final r = await Dio(BaseOptions(baseUrl: apiBase)).post('/auth/refresh/', data: {'refresh': refresh});
            await saveTokens(r.data['access'], r.data['refresh'] ?? refresh);
            final opts = e.requestOptions..extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer $access';
            return h.resolve(await _dio.fetch(opts));
          } catch (_) {
            await clearTokens();
          }
        }
        h.next(e);
      },
    ));

  String? access;
  String? refresh;

  Future<void> loadTokens() async {
    final p = await SharedPreferences.getInstance();
    access = p.getString('access');
    refresh = p.getString('refresh');
  }

  Future<void> saveTokens(String a, String r) async {
    access = a;
    refresh = r;
    final p = await SharedPreferences.getInstance();
    await p.setString('access', a);
    await p.setString('refresh', r);
  }

  Future<void> clearTokens() async {
    access = refresh = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('access');
    await p.remove('refresh');
  }

  Future<dynamic> _wrap(Future<Response> Function() call) async {
    try {
      final r = await call();
      return r.data;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) throw ApiError(data['message'].toString(), e.response?.statusCode);
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw ApiError("Can't reach Turflet. Check your internet connection.");
      }
      throw ApiError('Something went wrong (${e.response?.statusCode ?? 'network'}).', e.response?.statusCode);
    }
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? q]) => _wrap(() => _dio.get(path, queryParameters: q));
  Future<dynamic> post(String path, [Object? body]) => _wrap(() => _dio.post(path, data: body ?? {}));
  Future<dynamic> patch(String path, Object body) => _wrap(() => _dio.patch(path, data: body));
  Future<dynamic> put(String path, Object body) => _wrap(() => _dio.put(path, data: body));
  Future<dynamic> delete(String path) => _wrap(() => _dio.delete(path));
}

final api = Api.I;

List<Json> asList(dynamic v) => (v as List? ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
Json asMap(dynamic v) => (v as Map? ?? const {}).cast<String, dynamic>();
