import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../widgets.dart';
import 'bookings.dart';
import 'explore.dart';
import 'play.dart';
import 'profile.dart';
import 'squad.dart';

/// Main tabs: Explore · Bookings · Play · Squad · Profile
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pages = [
      const ExploreScreen(),
      _Gate(key: const ValueKey('b'), child: BookingsScreen(key: ValueKey('bk${s.user?['id']}'))),
      _Gate(key: const ValueKey('p'), child: PlayScreen(key: ValueKey('pl${s.user?['id']}'))),
      _Gate(key: const ValueKey('s'), child: SquadScreen(key: ValueKey('sq${s.user?['id']}'))),
      _Gate(key: const ValueKey('pr'), child: ProfileScreen(key: ValueKey('pf${s.user?['id']}'))),
    ];
    return Scaffold(
      body: IndexedStack(index: s.tab, children: pages),
      bottomNavigationBar: BottomNav(current: s.tab, onTap: (i) => s.setTab(i)),
    );
  }
}

/// Tabs that need an account show a sign-in prompt until the player verifies their number.
class _Gate extends StatelessWidget {
  final Widget child;
  const _Gate({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (context.watch<AppState>().loggedIn) return child;
    return SignInPrompt(onDone: () {});
  }
}
