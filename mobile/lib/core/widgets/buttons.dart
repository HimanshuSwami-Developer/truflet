import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';

/// The 44px rounded-square icon buttons used in headers.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool translucent;
  final double size, iconSize;
  final String? label;
  final Color iconColor;
  const SquareIconButton(
    this.icon, {
    super.key,
    this.onTap,
    this.translucent = false,
    this.size = 44,
    this.iconSize = 20,
    this.label,
    this.iconColor = C.ink,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: translucent ? Colors.white.withValues(alpha: 0.95) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: translucent ? BorderSide.none : const BorderSide(color: C.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      ),
    ),
  );
}

class BackSquare extends StatelessWidget {
  final bool translucent;
  final VoidCallback? onTap;
  const BackSquare({super.key, this.translucent = false, this.onTap});
  @override
  Widget build(BuildContext context) =>
      SquareIconButton(LucideIcons.chevronLeft, translucent: translucent, onTap: onTap, label: 'Back');
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height, radius, fontSize;
  final bool loading, shadow;
  final Widget? trailing;
  final Color color, fg;
  const PrimaryButton(
    this.label, {
    super.key,
    this.onTap,
    this.height = 56,
    this.radius = 18,
    this.loading = false,
    this.trailing,
    this.shadow = true,
    this.fontSize = 16,
    this.color = C.brand,
    this.fg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;
    return Container(
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadow && !disabled ? shadowBrand : null),
      child: Material(
        color: disabled ? C.line : color,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: t(fontSize, w: FontWeight.w600, c: disabled ? const Color(0xFF57625A) : fg),
                      ),
                      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height, radius;
  final IconData? icon;
  final Color fg, bg, border;
  final double fontSize;
  const GhostButton(
    this.label, {
    super.key,
    this.onTap,
    this.height = 52,
    this.radius = 16,
    this.icon,
    this.fg = C.ink,
    this.bg = Colors.white,
    this.border = C.line,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: border == Colors.transparent ? BorderSide.none : BorderSide(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  style: t(fontSize, w: FontWeight.w600, c: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
