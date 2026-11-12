import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Slot holds, payment, tickets, cancellation and rescheduling.
class BookingRepository {
  final ApiClient _api;
  BookingRepository(this._api);

  /// [tab] is upcoming | completed | cancelled. Returns `{items, counts}`.
  Future<Json> list(String tab) async => asMap(await _api.get('/bookings/', {'tab': tab}));

  Future<Json> details(int bookingId) async => asMap(await _api.get('/bookings/$bookingId/'));

  /// Holds the slot for a few minutes and returns the unpaid booking.
  Future<Json> hold(Json body) async => asMap(await _api.post('/bookings/', body));

  Future<void> reschedule(int bookingId, {required String date, required int? startHour, required dynamic courtId}) =>
      _api.post('/bookings/$bookingId/reschedule/', {'date': date, 'start_hour': startHour, 'court': courtId});

  /// Empty [code] removes the applied coupon. Returns the updated booking.
  Future<Json> applyCoupon(int bookingId, String code) async =>
      asMap(await _api.post('/bookings/$bookingId/coupon/', {'code': code}));

  Future<Json> pay(int bookingId, {required String method, required String upiId}) async =>
      asMap(await _api.post('/bookings/$bookingId/pay/', {'method': method, 'upi_id': upiId}));

  /// Refund the player would get if they cancelled now.
  Future<Json> cancelQuote(int bookingId) async => asMap(await _api.get('/bookings/$bookingId/cancel/'));

  Future<Json> cancel(int bookingId) async => asMap(await _api.post('/bookings/$bookingId/cancel/', {}));
}
