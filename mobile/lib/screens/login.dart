import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_form.dart';

/// Email + one-time code sign-in. Not in the original design; styled with the same tokens.
/// No passwords: the code is emailed and is valid for 10 minutes.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final code = TextEditingController();
  int step = 0; // 0 email, 1 code, 2 name
  bool busy = false;
  String? error, devCode;

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim());

  Future<void> _send() async {
    if (!_emailOk) {
      setState(() => error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = asMap(await api.post('/auth/otp/request/', {'email': email.text.trim()}));
      setState(() {
        step = 1;
        devCode = r['dev_code'];
        if (devCode != null) code.text = devCode!;
      });
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = asMap(await api.post('/auth/otp/verify/', {'email': email.text.trim(), 'code': code.text}));
      if (!mounted) return;
      await context.read<AppState>().setLoggedIn(r);
      if (r['is_new'] == true) {
        setState(() => step = 2);
      } else if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Sign in with email', 'Check your inbox', 'Complete your profile'];
    final subs = [
      "We'll email you a 6-digit code. No password needed — your bookings and QR pass stay linked to this email.",
      'We sent a 6-digit code to ${email.text.trim()}. It expires in 10 minutes. Check spam if you don\'t see it.',
      'Your name appears on bookings and in squads. The venue gets your mobile number so they can reach you.',
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          Align(alignment: Alignment.centerLeft, child: BackSquare(onTap: () {
            if (step == 1) {
              setState(() => step = 0);
            } else {
              Navigator.of(context).pop(context.read<AppState>().loggedIn);
            }
          })),
          const SizedBox(height: 28),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(20)),
            child: Icon(step == 2 ? LucideIcons.user : step == 1 ? LucideIcons.mailOpen : LucideIcons.mail, color: C.green700, size: 28),
          ),
          const SizedBox(height: 20),
          Text(titles[step], style: d(28, ls: -0.5)),
          const SizedBox(height: 8),
          Text(subs[step], style: t(15, c: C.muted, h: 1.5)),
          const SizedBox(height: 24),
          if (step == 0)
            _field(email, 'Email address', 'you@example.com', TextInputType.emailAddress, autofill: AutofillHints.email),
          if (step == 1)
            _field(code, '6-digit code', '••••••', TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], big: true),
          if (step == 2) ProfileForm(submitLabel: 'Save & continue', onSaved: () => Navigator.of(context).pop(true)),
          if (devCode != null && step == 1)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Dev mode: code $devCode was filled in for you (the server also prints the email).', style: t(12, c: C.muted)),
            ),
          if (error != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
              child: Text(error!, style: t(13, c: C.warnInk, h: 1.4)),
            ),
          if (step < 2) ...[
            const SizedBox(height: 24),
            PrimaryButton(step == 0 ? 'Send code' : 'Verify & continue', loading: busy, onTap: step == 0 ? _send : _verify),
          ],
          if (step == 1)
            TextButton(onPressed: busy ? null : _send, child: Text('Resend code', style: t(14, w: FontWeight.w600, c: C.brand))),
          if (step == 1)
            TextButton(
                onPressed: busy ? null : () => setState(() {
                      step = 0;
                      code.clear();
                      error = null;
                    }),
                child: Text('Use a different email', style: t(14, w: FontWeight.w600, c: C.muted))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(LucideIcons.shieldCheck, size: 14, color: C.muted),
            const SizedBox(width: 6),
            Text('We never share your email with advertisers', style: t(12, c: C.muted)),
          ]),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint, TextInputType type,
      {String? prefix, List<TextInputFormatter>? formatters, bool big = false, String? autofill}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t(13, w: FontWeight.w600)),
      const SizedBox(height: 8),
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
        child: Row(children: [
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
              onSubmitted: (_) => step == 0 ? _send() : _verify(),
              onChanged: (_) => setState(() {}),
              style: big ? d(22, ls: 8) : t(16),
              decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: t(16, c: C.muted), isDense: true),
            ),
          ),
        ]),
      ),
    ]);
  }
}
