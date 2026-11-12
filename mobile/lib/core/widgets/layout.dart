import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Uppercase grey section label.
class Label extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const Label(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 10)});
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      text.toUpperCase(),
      style: t(13, w: FontWeight.w600, c: C.muted, ls: 0.6),
    ),
  );
}

class H2 extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  const H2(this.text, {super.key, this.size = 18, this.color = C.ink});
  @override
  Widget build(BuildContext context) => Text(text, style: d(size, c: color));
}

class CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final List<BoxShadow>? shadow;
  final Border? border;
  final EdgeInsets? margin;
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.color = Colors.white,
    this.shadow = shadowSoft,
    this.border,
    this.margin,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: shadow, border: border),
    child: child,
  );
}

class KV extends StatelessWidget {
  final String k, v;
  final Color? vColor;
  final double vSize;
  const KV(this.k, this.v, {super.key, this.vColor, this.vSize = 14});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: t(11, c: C.muted)),
      const SizedBox(height: 2),
      Text(
        v,
        style: t(vSize, w: FontWeight.w700, c: vColor ?? C.ink),
      ),
    ],
  );
}

class PriceRow extends StatelessWidget {
  final String k, v;
  final bool bold, top;
  final Color? color;
  final double size;
  const PriceRow(this.k, this.v, {super.key, this.bold = false, this.top = false, this.color, this.size = 14});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(top: top ? 12 : 0),
    decoration: top
        ? const BoxDecoration(
            border: Border(top: BorderSide(color: C.line)),
          )
        : null,
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: t(size, w: bold ? FontWeight.w700 : FontWeight.w400, c: color ?? (bold ? C.ink : C.muted)),
          ),
        ),
        Text(
          v,
          style: t(size, w: bold ? FontWeight.w700 : FontWeight.w400, c: color ?? C.ink),
        ),
      ],
    ),
  );
}

class Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const Stat(this.label, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) => CardBox(
    padding: const EdgeInsets.all(12),
    radius: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t(11, c: C.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: d(18, c: color ?? C.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}
