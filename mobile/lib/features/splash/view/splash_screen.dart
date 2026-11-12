import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/theme/theme.dart';
import '../widgets/splash_mark.dart';

/// 1 · Splash: plays the logo animation, then routes to onboarding (first launch), location, or home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  /// Plays the logo story once: t hits the ball, ball bounces into place, t runs back in.
  late final intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: SplashMark.totalMs),
  );
  late final load = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (intro.status == AnimationStatus.dismissed) {
      // Respect "reduce motion": show the finished mark straight away.
      if (MediaQuery.of(context).disableAnimations) {
        intro.value = 1;
        Future.delayed(const Duration(milliseconds: 900), _next);
      } else {
        intro.forward().then((_) => Future.delayed(const Duration(milliseconds: 450), _next), onError: (_) {});
      }
    }
  }

  bool _left = false;

  /// After the intro: onboarding only on the first launch, then location (if not picked yet), else home.
  void _next() {
    if (!mounted || _left) return;
    _left = true;
    final s = context.read<AppCubit>().state;
    if (!s.onboarded) {
      context.goOnboarding();
    } else if (s.areaId == null) {
      context.goFirstLocation(fade: true);
    } else {
      context.goHome(fade: true);
    }
  }

  @override
  void dispose() {
    intro.dispose();
    load.dispose();
    super.dispose();
  }

  /// Fades/rises [child] in during [from]..[to] ms of the intro.
  Widget _reveal(int from, int to, Widget child) => AnimatedBuilder(
    animation: intro,
    builder: (_, c) {
      final p = Curves.easeOut.transform(SplashMark.iv(intro.value * SplashMark.totalMs, from, to));
      return Opacity(
        opacity: p,
        child: Transform.translate(offset: Offset(0, 14 * (1 - p)), child: c),
      );
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final markSize = math.min(240.0, mq.size.width * 0.6);
    return Scaffold(
      backgroundColor: Colors.white, // same white as the icon tile
      body: SizedBox(
        width: double.infinity, // keep the mark and logo centred horizontally
        child: Column(
          children: [
            SizedBox(height: mq.padding.top),
            const Spacer(flex: 3),
            SplashMark(animation: intro, size: markSize),
            const SizedBox(height: 32),
            _reveal(2000, 2500, Image.asset('assets/images/logo.png', height: 60, semanticLabel: 'Turflet')),
            const Spacer(flex: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 96,
                      height: 4,
                      color: C.line,
                      child: AnimatedBuilder(
                        animation: load,
                        builder: (_, _) => FractionalTranslation(
                          translation: Offset(-1 + 3.5 * Curves.easeInOut.transform(load.value), 0),
                          child: FractionallySizedBox(
                            widthFactor: 0.4,
                            alignment: Alignment.centerLeft,
                            child: Container(
                              decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(999)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
