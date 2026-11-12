import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import 'location.dart';
import 'onboarding.dart';
import 'shell.dart';

/// 1 · Splash
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  /// Plays the logo story once: t hits the ball, ball bounces into place, t runs back in.
  late final intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _SplashMark.totalMs),
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
    final s = context.read<AppState>();
    final Widget page = !s.onboarded
        ? const OnboardingScreen()
        : s.areaId == null
        ? const LocationScreen(first: true)
        : const MainShell();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
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
      final p = Curves.easeOut.transform(_SplashMark.iv(intro.value * _SplashMark.totalMs, from, to));
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
            _SplashMark(animation: intro, size: markSize),
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

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 48});
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/icon_rounded.png', width: size, height: size, semanticLabel: 'Turflet');
}

/// Animated Turflet mark. Positions are fractions of [size] and match the app icon
/// (the white tile is the full square).
class _SplashMark extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  const _SplashMark({required this.animation, required this.size});

  static const totalMs = 2500;

  // Final (icon) layout.
  static const _tX = 0.3057, _tY = 0.2395, _tW = 0.3554, _tH = 0.6205;
  static const _bX = 0.631, _bY = 0.1039, _bD = 0.2651;

  // Where the hit happens: t stands at the left, ball rests on the ground beside its foot.
  static const _hitTX = 0.03;
  static const _ballX0 = 0.425, _ballY0 = _tY + _tH - _bD;

  // Ball lands on its spot at these times (ms); used for the squash.
  static const _landings = [1150.0, 1450.0, 1660.0];

  /// Progress 0..1 of [ms] within [a]..[b].
  static double iv(double ms, num a, num b) => ((ms - a) / (b - a)).clamp(0.0, 1.0);
  static double _lerp(double a, double b, double p) => a + (b - a) * p;
  static double _deg(double d) => d * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, _) {
          final ms = animation.value * totalMs;
          // t + ball span x .31–.90 of the icon square; shift so the pair is visually centred.
          return Transform.translate(
            offset: Offset(-0.1 * size, 0),
            child: Stack(clipBehavior: Clip.none, children: [_impact(ms), _ball(ms), _t(ms)]),
          );
        },
      ),
    );
  }

  /// The "t": slides in, swings its foot through the ball, runs off left, then comes back in.
  Widget _t(double ms) {
    double x, angle;
    if (ms < 420) {
      // run in from the left, already leaning back for the swing
      final p = Curves.easeOutCubic.transform(iv(ms, 0, 420));
      x = _lerp(-1.3, _hitTX, p);
      angle = _lerp(8, 26, p);
    } else if (ms < 620) {
      // swing: foot sweeps right into the ball
      final p = Curves.easeInCubic.transform(iv(ms, 420, 620));
      x = _hitTX;
      angle = _lerp(26, -20, p);
    } else if (ms < 1000) {
      // follow through, then dash off to the left
      final p = iv(ms, 620, 1000);
      x = _lerp(_hitTX, -1.3, Curves.easeInCubic.transform(p));
      angle = _lerp(-20, 10, Curves.easeOut.transform(p));
    } else if (ms < 1600) {
      x = -1.3; // off stage while the ball bounces
      angle = 10;
    } else {
      // comes back from the left and settles into the icon position
      final p = iv(ms, 1600, 2150);
      x = _lerp(-1.3, _tX, Curves.easeOutBack.transform(p));
      angle = _lerp(14, 0, Curves.elasticOut.transform(iv(ms, 1600, 2300)));
    }
    return Positioned(
      left: x * size,
      top: _tY * size,
      width: _tW * size,
      height: _tH * size,
      child: Transform.rotate(
        angle: _deg(angle),
        alignment: Alignment.topCenter, // swings like a bat from the top
        child: Image.asset('assets/images/mark_t.png', fit: BoxFit.fill),
      ),
    );
  }

  /// The ball: rests, gets hit, flies up, bounces twice (tap tap) and settles.
  Widget _ball(double ms) {
    double x, y, sx = 1, sy = 1;
    const hitAt = 590.0;
    if (ms < hitAt) {
      x = _ballX0;
      y = _ballY0;
    } else if (ms < _landings[0]) {
      // arc from the ground up over its spot, then drop onto it
      final p = iv(ms, hitAt, _landings[0]);
      x = _lerp(_ballX0, _bX, Curves.easeOut.transform(p));
      y = _lerp(_ballY0, _bY, p) - 0.5 * 4 * p * (1 - p);
    } else {
      x = _bX;
      if (ms < _landings[1]) {
        final q = iv(ms, _landings[0], _landings[1]);
        y = _bY - 0.16 * 4 * q * (1 - q); // tap
      } else if (ms < _landings[2]) {
        final q = iv(ms, _landings[1], _landings[2]);
        y = _bY - 0.06 * 4 * q * (1 - q); // tap
      } else {
        y = _bY;
      }
    }
    // squash on each landing
    for (var i = 0; i < _landings.length; i++) {
      final d = (ms - _landings[i]).abs();
      if (d < 70) {
        final k = (1 - d / 70) * [1.0, 0.6, 0.3][i];
        sy = 1 - 0.2 * k;
        sx = 1 + 0.14 * k;
      }
    }
    final appear = Curves.easeOut.transform(iv(ms, 0, 220));
    return Positioned(
      left: x * size,
      top: y * size,
      width: _bD * size,
      height: _bD * size,
      child: Opacity(
        opacity: appear,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(sx * _lerp(0.6, 1, appear), sy * _lerp(0.6, 1, appear), 1),
          child: Image.asset('assets/images/mark_ball.png'),
        ),
      ),
    );
  }

  /// Small burst where the foot meets the ball.
  Widget _impact(double ms) {
    final p = iv(ms, 590, 820);
    if (p == 0 || p == 1) return const SizedBox.shrink();
    final d = _bD * size * _lerp(0.6, 1.8, Curves.easeOut.transform(p));
    final cx = (_ballX0 + _bD * 0.3) * size, cy = (_ballY0 + _bD * 0.7) * size;
    return Positioned(
      left: cx - d / 2,
      top: cy - d / 2,
      width: d,
      height: d,
      child: Opacity(
        opacity: 1 - p,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: C.brand, width: 3 * (1 - p) + 1),
          ),
        ),
      ),
    );
  }
}
