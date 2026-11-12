import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/session/app_cubit.dart';
import '../../auth/view/sign_in_prompt.dart';
import '../../booking/view/my_bookings_screen.dart';
import '../../explore/view/explore_screen.dart';
import '../../profile/view/profile_screen.dart';
import '../widgets/bottom_nav.dart';

/// Main tabs: Explore · Bookings · Profile (indexes in [AppTab])
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppCubit>();
    final s = app.state;
    // Keyed by player id so each tab starts fresh after signing in as someone else.
    final pages = [
      const ExploreScreen(),
      _Gate(
        key: const ValueKey('b'),
        child: MyBookingsScreen(key: ValueKey('bk${s.user?['id']}')),
      ),
      _Gate(
        key: const ValueKey('pr'),
        child: ProfileScreen(key: ValueKey('pf${s.user?['id']}')),
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: s.tab, children: pages),
      bottomNavigationBar: BottomNav(current: s.tab, onTap: (i) => app.setTab(i)),
    );
  }
}

/// Tabs that need an account show a sign-in prompt until the player verifies their email.
class _Gate extends StatelessWidget {
  final Widget child;
  const _Gate({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (context.watch<AppCubit>().loggedIn) return child;
    return SignInPrompt(onDone: () {});
  }
}
