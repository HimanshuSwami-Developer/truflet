import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/router/app_navigation.dart';
import '../../app/session/app_cubit.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import 'view/profile_form.dart';

/// Opens the email sign-in screen when needed. Returns true once the player is signed in.
Future<bool> requireLogin(BuildContext context) async {
  if (context.read<AppCubit>().loggedIn) return true;
  final ok = await context.pushLogin();
  return ok == true;
}

/// Signed in AND has name + mobile (needed before booking so the venue can reach the player).
Future<bool> requireProfile(BuildContext context) async {
  if (!await requireLogin(context)) return false;
  if (!context.mounted) return false;
  if (context.read<AppCubit>().state.user?['profile_complete'] == true) return true;
  final ok = await sheet<bool>(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Complete your profile', style: d(22)),
        const SizedBox(height: 6),
        Text('The venue needs your name and mobile number for this booking.', style: t(14, c: C.muted, h: 1.5)),
        const SizedBox(height: 16),
        ProfileForm(submitLabel: 'Save & continue', onSaved: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return ok == true;
}
