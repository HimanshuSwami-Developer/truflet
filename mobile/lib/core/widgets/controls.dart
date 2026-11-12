import 'package:flutter/material.dart';

import '../theme/theme.dart';

class Toggle extends StatelessWidget {
  final bool value;
  final Color on, off;
  const Toggle(this.value, {super.key, this.on = C.brand, this.off = C.dotOff});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    width: 48,
    height: 28,
    padding: const EdgeInsets.all(3),
    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
    decoration: BoxDecoration(color: value ? on : off, borderRadius: BorderRadius.circular(999)),
    child: Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    ),
  );
}

class RadioDot extends StatelessWidget {
  final bool on;
  const RadioDot(this.on, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
      border: Border.all(color: on ? C.brand : C.radioOff, width: on ? 7 : 2),
    ),
  );
}

/// Simple tappable wrapper with ink.
class Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color color;
  const Tap({super.key, required this.child, this.onTap, this.radius = 16, this.color = Colors.transparent});
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: child),
  );
}

/// Option tile with a border that turns green when selected (chips, pills, radios).
class Choice extends StatelessWidget {
  final bool selected;
  final Widget child;
  final VoidCallback onTap;
  final double radius, height;
  final Color selBg, selBorder;
  final double selWidth;
  final EdgeInsets padding;
  final bool filled;
  const Choice({
    super.key,
    required this.selected,
    required this.child,
    required this.onTap,
    this.radius = 14,
    this.height = 48,
    this.selBg = C.brand,
    this.selBorder = C.brand,
    this.selWidth = 1,
    this.filled = true,
    this.padding = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: height,
        padding: padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? selBg : Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: selected ? selBorder : C.line, width: selected ? selWidth : 1),
        ),
        child: child,
      ),
    ),
  );
}
