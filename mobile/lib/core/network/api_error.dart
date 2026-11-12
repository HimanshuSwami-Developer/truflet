import 'package:dio/dio.dart';

/// The one error type the UI sees. [message] is ready to show in a toast.
class ApiError implements Exception {
  final String message;
  final int? status;
  ApiError(this.message, [this.status]);

  /// Turns a Dio failure into a user-facing message.
  factory ApiError.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return ApiError(data['message'].toString(), e.response?.statusCode);
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return ApiError("Can't reach Turflet. Check your internet connection.");
    }
    return ApiError('Something went wrong (${e.response?.statusCode ?? 'network'}).', e.response?.statusCode);
  }

  @override
  String toString() => message;
}
