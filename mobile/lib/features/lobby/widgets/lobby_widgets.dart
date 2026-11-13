import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';

/// "Turf locked" (already paid) vs "Crowdfunding" (pool still filling, turf not booked yet).
class SlotStatePill extends StatelessWidget {
  final Json lobby;
  final double size;
  const SlotStatePill(this.lobby, {super.key, this.size = 11});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (lobby['status']) {
      'locked' => ('Turf locked', C.mint, C.green700, LucideIcons.lock),
      'crowdfunding' => ('Crowdfunding', C.amberSoft, C.amber, LucideIcons.piggyBank),
      'draft' => ('Awaiting payment', C.chip, C.mutedInk, LucideIcons.hourglass),
      'completed' => ('Played', C.chip, C.mutedInk, LucideIcons.circleCheck),
      'cancelled' => ('Cancelled', C.redSoft, C.redInk, LucideIcons.x),
      _ => ('Expired', C.chip, C.muted, LucideIcons.x),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: size + 1, color: fg),
          const SizedBox(width: 4),
          Text(label, style: t(size, w: FontWeight.w700, c: fg)),
        ],
      ),
    );
  }
}

/// Filled vs open spots (7/10).
class FillBar extends StatelessWidget {
  final int taken, capacity;
  final double height;
  const FillBar({super.key, required this.taken, required this.capacity, this.height = 6});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: LinearProgressIndicator(
      value: capacity == 0 ? 0 : (taken / capacity).clamp(0, 1).toDouble(),
      minHeight: height,
      backgroundColor: C.segment,
      color: C.brand,
    ),
  );
}

class AvatarStack extends StatelessWidget {
  final List<String> initials;
  final double size;
  final int max;
  const AvatarStack(this.initials, {super.key, this.size = 26, this.max = 5});

  @override
  Widget build(BuildContext context) {
    final n = initials.length.clamp(0, max);
    if (n == 0) return const SizedBox.shrink();
    final step = size * 0.62;
    return SizedBox(
      width: size + step * (n - 1),
      height: size,
      child: Stack(
        children: [
          for (var k = 0; k < n; k++)
            Positioned(
              left: k * step,
              child: Avatar(initials[k], index: k, size: size, ring: true),
            ),
        ],
      ),
    );
  }
}

/// Rebuilds every second with the time left until [until] (never negative).
class Countdown extends StatefulWidget {
  final DateTime until;
  final Widget Function(BuildContext context, Duration left) builder;
  const Countdown({super.key, required this.until, required this.builder});

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.until.difference(DateTime.now());
    return widget.builder(context, d.isNegative ? Duration.zero : d);
  }
}

String mmss(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Host reliability, e.g. "96% reliable · 12 hosted" or "New host".
String reliability(Json host) {
  final r = host['reliability'];
  if (r == null) return 'New host';
  return '$r% reliable · ${host['hosted']} hosted';
}

/// Per-head line: "₹265 /player" or "Free · host covers".
Widget perHead(Json lobby, {double size = 18}) {
  final amount = (lobby['per_head'] as int?) ?? 0;
  if (amount == 0) {
    return Text('Free · host pays', style: t(13, w: FontWeight.w700, c: C.brand));
  }
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: inr(amount), style: d(size, c: C.brand)),
        TextSpan(text: ' /player', style: t(12, c: C.muted)),
      ],
    ),
  );
}

/// Screen 3 card: host reliability, Turf Locked vs Crowdfunding, filled vs open spots, per-head cost and
/// a role-aware action (Request to join / Accept invite / Requested / Open Match Room).
class LobbyCard extends StatelessWidget {
  final Json lobby;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final bool showVenue;
  const LobbyCard({super.key, required this.lobby, this.onAction, this.onTap, this.showVenue = true});

  @override
  Widget build(BuildContext context) {
    final g = lobby;
    final host = asMap(g['host']);
    final taken = (g['taken'] as int?) ?? 0, capacity = (g['capacity'] as int?) ?? 0;
    final left = (g['spots_left'] as int?) ?? 0;
    final role = g['my_role'];
    final (label, bg, fg) = switch (role) {
      'host' => ('Your match', C.chip, C.mutedInk),
      'member' => ('Open room', C.mint, C.green700),
      'requested' => ('Requested', C.amberSoft, C.amber),
      'invited' => ('Accept invite', C.coral, Colors.white),
      'declined' => (left == 0 ? 'Full' : 'Request again', left == 0 ? C.chip : C.brand, left == 0 ? C.muted : Colors.white),
      _ => (left == 0 ? 'Full' : 'Request to join', left == 0 ? C.chip : C.brand, left == 0 ? C.muted : Colors.white),
    };
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: shadowCard, color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SportPill(asMap(g['sport'])),
                  const SizedBox(width: 6),
                  SlotStatePill(g),
                  const Spacer(),
                  perHead(g),
                ],
              ),
              const SizedBox(height: 10),
              Text('${g['date_label']} · ${g['time_label']}', style: d(17)),
              const SizedBox(height: 2),
              Text(
                [
                  if (showVenue) '${g['venue']?['name']}, ${g['venue']?['area']} · ${g['court']?['name']}',
                  if (!showVenue) '${g['court']?['name']}',
                ].join(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t(13, c: C.muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Avatar(host['initials'] ?? '', size: 28, index: 1),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role == 'invited' ? '${host['name'] ?? ''} invited you' : 'Hosted by ${host['name'] ?? ''}',
                          style: t(13, w: FontWeight.w600, c: role == 'invited' ? C.orangeInk : C.ink),
                        ),
                        Row(
                          children: [
                            Icon(
                              host['reliability'] == null ? LucideIcons.sparkles : LucideIcons.shieldCheck,
                              size: 12,
                              color: C.green700,
                            ),
                            const SizedBox(width: 4),
                            Text(reliability(host), style: t(11, c: C.green700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FillBar(taken: taken, capacity: capacity),
              const SizedBox(height: 8),
              Row(
                children: [
                  AvatarStack((g['avatars'] as List? ?? const []).cast<String>()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$taken/$capacity joined · ${left == 0 ? 'full' : '$left spot${left == 1 ? '' : 's'} open'}',
                      style: t(12, c: C.muted),
                    ),
                  ),
                  if (onAction != null)
                    GhostButton(
                      label,
                      height: 38,
                      radius: 12,
                      fontSize: 13,
                      bg: bg,
                      fg: fg,
                      border: Colors.transparent,
                      onTap: (role == null || role == 'declined') && left == 0 ? null : onAction,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty / info card with an icon.
class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? action;
  const EmptyNote({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 40, color: C.muted),
        const SizedBox(height: 12),
        Text(title, style: d(18), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center, style: t(14, c: C.muted, h: 1.5)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
