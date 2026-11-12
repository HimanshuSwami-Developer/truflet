import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/api_error.dart';

class ProfileFormState {
  /// Field errors keyed by name | phone | form.
  final Map<String, String> errors;
  final bool busy;
  const ProfileFormState({this.errors = const {}, this.busy = false});
}

/// Validates and saves name, mobile, address (and handle) on the player's profile.
class ProfileFormCubit extends Cubit<ProfileFormState> {
  final AppCubit _app;
  ProfileFormCubit({required this._app}) : super(const ProfileFormState());

  bool validate({required String name, required String phone}) {
    final errors = <String, String>{};
    if (name.trim().length < 2) errors['name'] = 'Please enter your name.';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      errors['phone'] = 'Please enter your mobile number.';
    } else if (digits.length != 10) {
      errors['phone'] = 'Enter a 10-digit mobile number.';
    }
    _emit(ProfileFormState(errors: errors, busy: state.busy));
    return errors.isEmpty;
  }

  void clearError(String key) => _emit(ProfileFormState(errors: {...state.errors}..remove(key), busy: state.busy));

  /// Returns true when saved.
  Future<bool> save({required String name, required String phone, required String address, String? handle}) async {
    if (!validate(name: name, phone: phone)) return false;
    _emit(ProfileFormState(errors: state.errors, busy: true));
    try {
      await _app.updateMe({
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'handle': ?handle?.trim().replaceAll('@', ''),
      });
      return true;
    } on ApiError catch (e) {
      _emit(ProfileFormState(errors: {...state.errors, 'form': e.message}, busy: state.busy));
      return false;
    } finally {
      _emit(ProfileFormState(errors: state.errors, busy: false));
    }
  }

  void _emit(ProfileFormState s) {
    if (!isClosed) emit(s);
  }
}
