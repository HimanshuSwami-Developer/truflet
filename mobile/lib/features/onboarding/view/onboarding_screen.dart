import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';

/// 2 · Onboarding (3 slides). Shown once after install; Skip / Get started saves that it was seen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  final String img, title, body;
  const _Slide(this.img, this.title, this.body);
}

const _slides = [
  _Slide(
    'cricket',
    'Find the best turfs near you',
    'Box cricket, football pitches, badminton and pickleball courts — all in one place, sorted by distance.',
  ),
  _Slide(
    'badminton_court',
    'Pick your slot like a movie seat',
    'Live availability by date, court and time. Choose a start time and duration in two taps.',
  ),
  _Slide(
    'football',
    'Pay securely, show up & play',
    'UPI, cards or wallets. Get instant confirmation and a QR pass for check-in.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pc = PageController();
  int i = 0;

  void _done() async {
    await context.read<AppCubit>().finishOnboarding();
    if (!mounted) return;
    context.goFirstLocation();
  }

  void _go(int n) => pc.animateToPage(n, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final s = _slides[i];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  Image.asset('assets/images/logo.png', height: 28, semanticLabel: 'Turflet'),
                  const Spacer(),
                  GhostButton('Skip', onTap: _done, height: 40, radius: 999, fg: C.muted),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 420),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [BoxShadow(color: Color(0x2910231A), blurRadius: 44, offset: Offset(0, 20))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: PageView.builder(
                      controller: pc,
                      itemCount: _slides.length,
                      onPageChanged: (n) => setState(() => i = n),
                      itemBuilder: (_, n) {
                        final sl = _slides[n];
                        return Image.asset('assets/images/${sl.img}.jpg', fit: BoxFit.cover);
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var k = 0; k < 3; k++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 6),
                          width: k == i ? 28 : 6,
                          height: 6,
                          decoration: BoxDecoration(color: k == i ? C.brand : C.dotOff, borderRadius: BorderRadius.circular(999)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 66,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width - 56,
                          child: Text(s.title, style: d(28, h: 1.15, ls: -0.5)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(s.body, style: t(15, c: C.muted, h: 1.55)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + MediaQuery.of(context).padding.bottom / 2),
              child: Row(
                children: [
                  if (i > 0) ...[
                    SquareIconButton(LucideIcons.chevronLeft, size: 56, iconSize: 22, label: 'Previous', onTap: () => _go(i - 1)),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: PrimaryButton(i < 2 ? 'Next' : 'Get started', onTap: i < 2 ? () => _go(i + 1) : _done)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
