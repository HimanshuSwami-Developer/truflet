import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/theme/theme.dart';

/// Shared bottom navigation: Explore · Bookings · Profile.
class BottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.current, required this.onTap});

  static const items = [(LucideIcons.house, 'Explore'), (LucideIcons.calendar, 'Bookings'), (LucideIcons.user, 'Profile')];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 64 + (bottom > 0 ? bottom : 12),
      padding: EdgeInsets.fromLTRB(6, 8, 6, bottom > 0 ? bottom : 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                      Text(
                        items[i].$2,
                        style: t(11, w: i == current ? FontWeight.w700 : FontWeight.w500, c: i == current ? C.brand : C.muted),
                      ),
                    ],
                  ),
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
    bottomNavigationBar: BottomNav(current: current, onTap: (i) => context.goTab(i)),
  );
}
