import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../auth_guard.dart';

/// Shown on tabs that need a signed-in player.
class SignInPrompt extends StatelessWidget {
  final VoidCallback onDone;
  const SignInPrompt({super.key, required this.onDone});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(28)),
              child: const Icon(LucideIcons.mail, size: 36, color: C.green700),
            ),
            const SizedBox(height: 16),
            Text('Sign in to continue', style: d(20)),
            const SizedBox(height: 8),
            Text(
              'Your bookings are linked to your email. We send a one-time code — no password.',
              textAlign: TextAlign.center,
              style: t(14, c: C.muted, h: 1.5),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              'Continue with email',
              onTap: () async {
                if (await requireLogin(context)) onDone();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
