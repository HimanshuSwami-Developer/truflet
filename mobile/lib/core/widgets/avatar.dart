import 'package:flutter/material.dart';

import '../theme/theme.dart';

const avatarColors = [C.brand, C.blue, C.purple, C.orange, C.teal, C.amber, C.redInk, Color(0xFF0F766E)];

class Avatar extends StatelessWidget {
  final String initials;
  final int index;
  final double size;
  final bool ring, square;
  const Avatar(this.initials, {super.key, this.index = 0, this.size = 44, this.ring = false, this.square = false});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: avatarColors[index % avatarColors.length],
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(12) : null,
      border: ring ? Border.all(color: Colors.white, width: 2) : null,
    ),
    child: Text(
      initials,
      style: t((size * 0.33).roundToDouble(), w: FontWeight.w700, c: Colors.white),
    ),
  );
}
