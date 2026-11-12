import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/auth_repository.dart';
import '../cubit/login_cubit.dart';
import '../cubit/login_state.dart';
import 'profile_form.dart';

/// Email + one-time code sign-in. Not in the original design; styled with the same tokens.
/// No passwords: the code is emailed and is valid for 10 minutes.
/// Pops with `true` once the player is signed in.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => LoginCubit(repository: c.read<AuthRepository>(), app: c.read<AppCubit>()),
    child: const _LoginView(),
  );
}

class _LoginView extends StatefulWidget {
  const _LoginView();
  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final email = TextEditingController();
  final code = TextEditingController();

  LoginCubit get _cubit => context.read<LoginCubit>();

  Future<void> _send() async {
    final dev = await _cubit.sendCode(email.text.trim());
    if (dev != null) code.text = dev;
  }

  Future<void> _verify() async {
    final done = await _cubit.verifyCode(email.text.trim(), code.text);
    if (done && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<LoginCubit, LoginState>(builder: _build);

  Widget _build(BuildContext context, LoginState st) {
    final step = st.step.index; // 0 email, 1 code, 2 profile
    final busy = st.busy, error = st.error, devCode = st.devCode;
    final titles = ['Sign in with email', 'Check your inbox', 'Complete your profile'];
    final subs = [
      "We'll email you a 6-digit code. No password needed — your bookings and QR pass stay linked to this email.",
      'We sent a 6-digit code to ${email.text.trim()}. It expires in 10 minutes. Check spam if you don\'t see it.',
      'Your name appears on bookings and in squads. The venue gets your mobile number so they can reach you.',
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BackSquare(
                onTap: () {
                  if (step == 1) {
                    _cubit.backToEmail();
                  } else {
                    Navigator.of(context).pop(context.read<AppCubit>().loggedIn);
                  }
                },
              ),
            ),
            const SizedBox(height: 28),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(20)),
              child: Icon(
                step == 2
                    ? LucideIcons.user
                    : step == 1
                    ? LucideIcons.mailOpen
                    : LucideIcons.mail,
                color: C.green700,
                size: 28,
              ),
            ),
            const SizedBox(height: 20),
            Text(titles[step], style: d(28, ls: -0.5)),
            const SizedBox(height: 8),
            Text(subs[step], style: t(15, c: C.muted, h: 1.5)),
            const SizedBox(height: 24),
            if (step == 0)
              _field(email, 'Email address', 'you@example.com', TextInputType.emailAddress, autofill: AutofillHints.email),
            if (step == 1)
              _field(
                code,
                '6-digit code',
                '••••••',
                TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                big: true,
              ),
            if (step == 2) ProfileForm(submitLabel: 'Save & continue', onSaved: () => Navigator.of(context).pop(true)),
            if (devCode != null && step == 1)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Dev mode: code $devCode was filled in for you (the server also prints the email).',
                  style: t(12, c: C.muted),
                ),
              ),
            if (error != null)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
                child: Text(error, style: t(13, c: C.warnInk, h: 1.4)),
              ),
            if (step < 2) ...[
              const SizedBox(height: 24),
              PrimaryButton(step == 0 ? 'Send code' : 'Verify & continue', loading: busy, onTap: step == 0 ? _send : _verify),
            ],
            if (step == 1)
              TextButton(
                onPressed: busy ? null : _send,
                child: Text(
                  'Resend code',
                  style: t(14, w: FontWeight.w600, c: C.brand),
                ),
              ),
            if (step == 1)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        code.clear();
                        _cubit.backToEmail(clearError: true);
                      },
                child: Text(
                  'Use a different email',
                  style: t(14, w: FontWeight.w600, c: C.muted),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(LucideIcons.shieldCheck, size: 14, color: C.muted),
                const SizedBox(width: 6),
                Text('We never share your email with advertisers', style: t(12, c: C.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint,
    TextInputType type, {
    String? prefix,
    List<TextInputFormatter>? formatters,
    bool big = false,
    String? autofill,
  }) {
    final step = context.read<LoginCubit>().state.step;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t(13, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
          child: Row(
            children: [
              if (prefix != null) ...[Text(prefix, style: t(16, w: FontWeight.w600)), const SizedBox(width: 10)],
              Expanded(
                child: TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: type,
                  inputFormatters: formatters,
                  autocorrect: false,
                  textCapitalization: autofill == AutofillHints.email ? TextCapitalization.none : TextCapitalization.words,
                  autofillHints: autofill == null ? null : [autofill],
                  onSubmitted: (_) => step == LoginStep.email ? _send() : _verify(),
                  onChanged: (_) => setState(() {}), // subtitle shows the typed email
                  style: big ? d(22, ls: 8) : t(16),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: t(16, c: C.muted),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
