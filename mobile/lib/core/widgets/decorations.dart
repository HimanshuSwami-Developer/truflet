import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Ticket perforation: dashed line with half-circle cut-outs on both sides.
class Perforation extends StatelessWidget {
  final double height, notch;
  const Perforation({super.key, this.height = 22, this.notch = 22});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -notch / 2,
          child: Container(
            width: notch,
            height: notch,
            decoration: const BoxDecoration(color: C.ground, shape: BoxShape.circle),
          ),
        ),
        Positioned(
          right: -notch / 2,
          child: Container(
            width: notch,
            height: notch,
            decoration: const BoxDecoration(color: C.ground, shape: BoxShape.circle),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: CustomPaint(size: const Size(double.infinity, 2), painter: _Dash()),
        ),
      ],
    ),
  );
}

class _Dash extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = C.line
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, 0), Offset((x + 5).clamp(0, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class DashedBorderBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color color;
  const DashedBorderBox({super.key, required this.child, this.radius = 20, this.color = const Color(0xFFB9C8BC)});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DashRect(radius, color), child: child);
}

class _DashRect extends CustomPainter {
  final double r;
  final Color color;
  _DashRect(this.r, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)));
    for (final m in path.computeMetrics()) {
      for (double dd = 0; dd < m.length; dd += 10) {
        canvas.drawPath(m.extractPath(dd, dd + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
