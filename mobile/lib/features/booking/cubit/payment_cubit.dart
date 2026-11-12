import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/booking_repository.dart';

class PaymentState {
  final Json booking;
  final String method;
  final bool busy, couponBusy;
  final String? couponError;

  /// Time left on the slot hold.
  final Duration left;

  const PaymentState({
    required this.booking,
    this.method = 'upi',
    this.busy = false,
    this.couponBusy = false,
    this.couponError,
    this.left = Duration.zero,
  });

  bool get couponApplied => booking['coupon'] != null;

  static const _keep = Object();

  PaymentState copyWith({
    Json? booking,
    String? method,
    bool? busy,
    bool? couponBusy,
    Object? couponError = _keep,
    Duration? left,
  }) => PaymentState(
    booking: booking ?? this.booking,
    method: method ?? this.method,
    busy: busy ?? this.busy,
    couponBusy: couponBusy ?? this.couponBusy,
    couponError: identical(couponError, _keep) ? this.couponError : couponError as String?,
    left: left ?? this.left,
  );
}

/// 7 · Review & pay: hold countdown, coupon, payment method.
class PaymentCubit extends Cubit<PaymentState> {
  final BookingRepository _repo;
  final AppCubit _app;
  Timer? _timer;

  PaymentCubit({required Json booking, required BookingRepository repository, required this._app})
    : _repo = repository,
      super(PaymentState(booking: booking)) {
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final until = DateTime.tryParse(state.booking['held_until'] ?? '');
    if (until == null) return;
    final d = until.difference(DateTime.now());
    _emit(state.copyWith(left: d.isNegative ? Duration.zero : d));
  }

  void selectMethod(String m) => _emit(state.copyWith(method: m));

  /// Applies [code], or removes the applied coupon. Returns true when a coupon was removed.
  Future<bool> toggleCoupon(String code) async {
    final applied = state.couponApplied;
    _emit(state.copyWith(couponBusy: true, couponError: null));
    try {
      final r = await _repo.applyCoupon(state.booking['id'], applied ? '' : code.trim());
      _emit(state.copyWith(booking: r));
      return applied;
    } catch (e) {
      _emit(state.copyWith(couponError: e.toString()));
      return false;
    } finally {
      _emit(state.copyWith(couponBusy: false));
    }
  }

  /// Pays for the held slot. Returns the confirmed booking, or an error message to show.
  Future<({Json? booking, String? error})> pay(String upiId) async {
    if (state.left == Duration.zero) return (booking: null, error: 'Your slot hold expired. Please pick the slot again.');
    _emit(state.copyWith(busy: true));
    try {
      final r = await _repo.pay(state.booking['id'], method: state.method, upiId: upiId.trim());
      _app.refreshMe(); // wallet balance may have changed
      return (booking: r, error: null);
    } catch (e) {
      return (booking: null, error: e.toString());
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  void _emit(PaymentState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
