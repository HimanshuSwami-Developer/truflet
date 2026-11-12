import 'package:flutter/material.dart';

import '../network/json.dart';
import '../theme/theme.dart';

class Pill extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final double size;
  final EdgeInsets padding;
  const Pill(
    this.label, {
    super.key,
    this.bg = C.mint,
    this.fg = C.green700,
    this.size = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      label,
      style: t(size, w: FontWeight.w700, c: fg),
    ),
  );
}

/// Sport-coloured chip from an API sport map ({name, fg, bg}).
class SportPill extends StatelessWidget {
  final Json sport;
  final String? label;
  final double size;
  const SportPill(this.sport, {super.key, this.label, this.size = 11});
  @override
  Widget build(BuildContext context) => Pill(
    label ?? sport['name'] ?? '',
    bg: hex(sport['bg'], C.mint),
    fg: hex(sport['fg']),
    size: size,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
  );
}
