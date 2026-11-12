import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'screens/login.dart';
import 'screens/profile_form.dart';
import 'state.dart';
import 'theme.dart';

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2400)));
}

/// Pushes the OTP login screen when needed. Returns true once the user is signed in.
Future<bool> requireLogin(BuildContext context) async {
  if (context.read<AppState>().loggedIn) return true;
  final ok = await push<bool>(context, const LoginScreen());
  return ok == true;
}

/// Signed in AND has name + mobile (needed before booking so the venue can reach the player).
Future<bool> requireProfile(BuildContext context) async {
  if (!await requireLogin(context)) return false;
  if (!context.mounted) return false;
  if (context.read<AppState>().user?['profile_complete'] == true) return true;
  final ok = await sheet<bool>(context, (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Complete your profile', style: d(22)),
        const SizedBox(height: 6),
        Text('The venue needs your name and mobile number for this booking.', style: t(14, c: C.muted, h: 1.5)),
        const SizedBox(height: 16),
        ProfileForm(submitLabel: 'Save & continue', onSaved: () => Navigator.pop(ctx, true)),
      ]));
  return ok == true;
}

/// Leaves a pushed screen and switches the bottom-nav tab.
void goTab(BuildContext context, int i) {
  context.read<AppState>().setTab(i);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// Network image (Cloudinary / Django media) with the app's placeholder colour.
class Img extends StatelessWidget {
  final String? url;
  final double? width, height;
  final BorderRadius? radius;
  final String fallback;
  const Img(this.url, {super.key, this.width, this.height, this.radius, this.fallback = 'turf'});

  @override
  Widget build(BuildContext context) {
    final Widget child = (url == null || url!.isEmpty)
        ? Image.asset('assets/images/$fallback.jpg', width: width, height: height, fit: BoxFit.cover)
        : CachedNetworkImage(
            imageUrl: url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => Container(color: const Color(0xFFE8F0E4)),
            errorWidget: (_, _, _) => Image.asset('assets/images/$fallback.jpg', fit: BoxFit.cover),
          );
    return radius == null ? child : ClipRRect(borderRadius: radius!, child: child);
  }
}

class Pill extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final double size;
  final EdgeInsets padding;
  const Pill(this.label, {super.key, this.bg = C.mint, this.fg = C.green700, this.size = 11,
      this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: t(size, w: FontWeight.w700, c: fg)),
      );
}

/// Sport-coloured chip from an API sport map ({name, fg, bg}).
class SportPill extends StatelessWidget {
  final Json sport;
  final String? label;
  final double size;
  const SportPill(this.sport, {super.key, this.label, this.size = 11});
  @override
  Widget build(BuildContext context) => Pill(label ?? sport['name'] ?? '', bg: hex(sport['bg'], C.mint), fg: hex(sport['fg']),
      size: size, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3));
}

/// The 44px rounded-square icon buttons used in headers.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool translucent;
  final double size, iconSize;
  final String? label;
  final Color iconColor;
  const SquareIconButton(this.icon, {super.key, this.onTap, this.translucent = false, this.size = 44, this.iconSize = 20,
      this.label, this.iconColor = C.ink});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: translucent ? Colors.white.withValues(alpha: 0.95) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: translucent ? BorderSide.none : const BorderSide(color: C.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap ?? () => Navigator.of(context).maybePop(),
            child: SizedBox(width: size, height: size, child: Icon(icon, size: iconSize, color: iconColor)),
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
  const PrimaryButton(this.label, {super.key, this.onTap, this.height = 56, this.radius = 18, this.loading = false,
      this.trailing, this.shadow = true, this.fontSize = 16, this.color = C.brand, this.fg = Colors.white});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !loading;
    return Container(
      height: height,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius), boxShadow: shadow && !disabled ? shadowBrand : null),
      child: Material(
        color: disabled ? C.line : color,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: t(fontSize, w: FontWeight.w600, c: disabled ? const Color(0xFF57625A) : fg)),
                    if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                  ]),
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
  const GhostButton(this.label, {super.key, this.onTap, this.height = 52, this.radius = 16, this.icon, this.fg = C.ink,
      this.bg = Colors.white, this.border = C.line, this.fontSize = 14});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: border == Colors.transparent ? BorderSide.none : BorderSide(color: border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
                Flexible(child: Text(label, style: t(fontSize, w: FontWeight.w600, c: fg), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
      );
}

/// Grey segmented tab bar (Upcoming / Completed / Cancelled, etc.).
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final List<int>? counts;
  final List<int>? badges;
  final Color bg;
  final double height;
  const Segmented({super.key, required this.labels, required this.index, required this.onChanged, this.counts,
      this.badges, this.bg = C.segment, this.height = 42});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  selected: i == index,
                  button: true,
                  child: GestureDetector(
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: height,
                      decoration: BoxDecoration(
                        color: i == index ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: i == index ? const [BoxShadow(color: Color(0x1F10231A), blurRadius: 3, offset: Offset(0, 1))] : null,
                      ),
                      alignment: Alignment.center,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Flexible(
                          child: Text(labels[i],
                              overflow: TextOverflow.ellipsis,
                              style: t(13, w: FontWeight.w600, c: i == index ? C.ink : C.muted)),
                        ),
                        if (counts != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: i == index ? C.brand : const Color(0xFFD9E2D5), borderRadius: BorderRadius.circular(999)),
                            child: Text('${counts![i]}', style: t(11, c: i == index ? Colors.white : C.mutedInk)),
                          ),
                        ],
                        if (badges != null && badges![i] > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            height: 18,
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: const Color(0xFFEA580C), borderRadius: BorderRadius.circular(999)),
                            child: Text('${badges![i]}', style: t(11, c: Colors.white)),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

/// Uppercase grey section label.
class Label extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const Label(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 10)});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text.toUpperCase(), style: t(13, w: FontWeight.w600, c: C.muted, ls: 0.6)));
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
  const CardBox({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20,
      this.color = Colors.white, this.shadow = shadowSoft, this.border, this.margin});
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: shadow, border: border),
        child: child,
      );
}

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
        child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
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
        child: Text(initials, style: t((size * 0.33).roundToDouble(), w: FontWeight.w700, c: Colors.white)),
      );
}

class KV extends StatelessWidget {
  final String k, v;
  final Color? vColor;
  final double vSize;
  const KV(this.k, this.v, {super.key, this.vColor, this.vSize = 14});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: t(11, c: C.muted)),
        const SizedBox(height: 2),
        Text(v, style: t(vSize, w: FontWeight.w700, c: vColor ?? C.ink)),
      ]);
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
        decoration: top ? const BoxDecoration(border: Border(top: BorderSide(color: C.line))) : null,
        child: Row(children: [
          Expanded(child: Text(k, style: t(size, w: bold ? FontWeight.w700 : FontWeight.w400, c: color ?? (bold ? C.ink : C.muted)))),
          Text(v, style: t(size, w: bold ? FontWeight.w700 : FontWeight.w400, c: color ?? C.ink)),
        ]),
      );
}

/// Ticket perforation: dashed line with half-circle cut-outs on both sides.
class Perforation extends StatelessWidget {
  final double height, notch;
  const Perforation({super.key, this.height = 22, this.notch = 22});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Positioned(
              left: -notch / 2,
              child: Container(width: notch, height: notch, decoration: const BoxDecoration(color: C.ground, shape: BoxShape.circle))),
          Positioned(
              right: -notch / 2,
              child: Container(width: notch, height: notch, decoration: const BoxDecoration(color: C.ground, shape: BoxShape.circle))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: CustomPaint(size: const Size(double.infinity, 2), painter: _Dash())),
        ]),
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

/// Bottom sheet chrome used across the app (handle + rounded top).
Future<T?> sheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x7310231A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: C.dashed, borderRadius: BorderRadius.circular(999)))),
          const SizedBox(height: 14),
          builder(ctx),
        ]),
      ),
    );

/// Loads a future and shows a spinner / retry on error.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  const Loader({super.key, required this.load, required this.builder});
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? data;
  String? error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final r = await widget.load();
      if (mounted) {
        setState(() {
        data = r;
        error = null;
      });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data != null) return widget.builder(context, data as T, reload);
    if (error != null) {
      return ErrorRetry(error!, onRetry: () {
      setState(() => error = null);
      reload();
    });
    }
    return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: C.brand)));
  }
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry(this.message, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.wifiOff, size: 36, color: C.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: t(14, c: C.muted, h: 1.5)),
            const SizedBox(height: 16),
            GhostButton('Try again', onTap: onRetry, height: 44),
          ]),
        ),
      );
}

/// Shared bottom navigation: Explore · Bookings · Play · Squad · Profile.
class BottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.current, required this.onTap});

  static const items = [
    (LucideIcons.house, 'Explore'),
    (LucideIcons.calendar, 'Bookings'),
    (LucideIcons.trophy, 'Play'),
    (LucideIcons.users, 'Squad'),
    (LucideIcons.user, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 64 + (bottom > 0 ? bottom : 12),
      padding: EdgeInsets.fromLTRB(6, 8, 6, bottom > 0 ? bottom : 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == current,
                button: true,
                label: items[i].$2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTap(i),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (i == current)
                      Container(
                        width: 48,
                        height: 30,
                        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(999)),
                        child: Icon(items[i].$1, size: 20, color: C.brand),
                      )
                    else
                      SizedBox(height: 30, child: Icon(items[i].$1, size: 22, color: C.muted)),
                    const SizedBox(height: 4),
                    Text(items[i].$2,
                        style: t(11, w: i == current ? FontWeight.w700 : FontWeight.w500, c: i == current ? C.brand : C.muted)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wrapper for pushed screens that still show the bottom nav (Saved, Help).
class WithNav extends StatelessWidget {
  final int current;
  final Widget child;
  const WithNav({super.key, required this.current, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        bottomNavigationBar: BottomNav(current: current, onTap: (i) => goTab(context, i)),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t(11, c: C.muted)),
          const SizedBox(height: 2),
          Text(value, style: d(18, c: color ?? C.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
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
  const Choice({super.key, required this.selected, required this.child, required this.onTap, this.radius = 14,
      this.height = 48, this.selBg = C.brand, this.selBorder = C.brand, this.selWidth = 1, this.filled = true,
      this.padding = EdgeInsets.zero});
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

/// Shown on tabs that need a signed-in player.
class SignInPrompt extends StatelessWidget {
  final VoidCallback onDone;
  const SignInPrompt({super.key, required this.onDone});
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(28)),
                child: const Icon(LucideIcons.mail, size: 36, color: C.green700),
              ),
              const SizedBox(height: 16),
              Text('Sign in to continue', style: d(20)),
              const SizedBox(height: 8),
              Text('Your bookings, squads and tournaments are linked to your email. We send a one-time code — no password.',
                  textAlign: TextAlign.center, style: t(14, c: C.muted, h: 1.5)),
              const SizedBox(height: 20),
              PrimaryButton('Continue with email', onTap: () async {
                if (await requireLogin(context)) onDone();
              }),
            ]),
          ),
        ),
      );
}
