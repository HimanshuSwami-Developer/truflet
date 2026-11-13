import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/json.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/booking/view/booking_confirmed_screen.dart';
import '../../features/booking/view/payment_screen.dart';
import '../../features/booking/view/slot_booking_screen.dart';
import '../../features/booking/view/ticket_screen.dart';
import '../../features/lobby/view/lobbies_screen.dart';
import '../../features/lobby/view/match_room_screen.dart';
import '../../features/lobby/view/request_thread_screen.dart';
import '../../features/lobby/view/squad_builder_screen.dart';
import '../../features/location/view/location_screen.dart';
import '../../features/notifications/view/notifications_screen.dart';
import '../../features/onboarding/view/onboarding_screen.dart';
import '../../features/saved/view/saved_screen.dart';
import '../../features/shell/view/main_shell.dart';
import '../../features/splash/view/splash_screen.dart';
import '../../features/support/view/help_screen.dart';
import '../../features/support/view/policy_screen.dart';
import '../../features/venue/view/venue_details_screen.dart';
import 'app_routes.dart';

/// All routes. Screens navigate with the helpers in app_navigation.dart.
GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    _route(AppRoutes.splash, (s) => const SplashScreen()),
    _route(AppRoutes.onboarding, (s) => const OnboardingScreen()),
    _route(AppRoutes.location, (s) => LocationScreen(first: s.uri.queryParameters['first'] == '1')),
    _route(AppRoutes.home, (s) => const MainShell()),
    _route(AppRoutes.login, (s) => const LoginScreen()),
    _route(AppRoutes.notifications, (s) => const NotificationsScreen()),
    _route(AppRoutes.saved, (s) => const SavedScreen()),
    _route(AppRoutes.help, (s) => HelpScreen(booking: s.extra as Json?)),
    _route(AppRoutes.policy, (s) => PolicyScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
    _route(AppRoutes.venue, (s) => VenueDetailsScreen(venueId: int.parse(s.pathParameters['venueId']!))),
    _route(AppRoutes.slotBooking, (s) => SlotBookingScreen(args: s.extra! as SlotBookingArgs)),
    _route(AppRoutes.payment, (s) => PaymentScreen(booking: s.extra! as Json)),
    _route(AppRoutes.bookingConfirmed, (s) => BookingConfirmedScreen(booking: s.extra! as Json)),
    _route(AppRoutes.lobbies, (s) => LobbiesScreen(args: s.extra! as LobbiesArgs)),
    _route(AppRoutes.squad, (s) => SquadBuilderScreen(args: s.extra! as SquadArgs)),
    _route(AppRoutes.match, (s) => MatchRoomScreen(lobbyId: int.parse(s.pathParameters['lobbyId']!))),
    _route(
      AppRoutes.requestThread,
      (s) => RequestThreadScreen(
        lobbyId: int.parse(s.pathParameters['lobbyId']!),
        requestId: int.parse(s.pathParameters['requestId']!),
      ),
    ),
    _route(AppRoutes.ticket, (s) => TicketScreen(bookingId: int.parse(s.pathParameters['bookingId']!))),
  ],
);

/// Platform page transition, or the splash cross-fade when navigated with `extra: FadeIn()`.
GoRoute _route(String path, Widget Function(GoRouterState) build) => GoRoute(
  path: path,
  pageBuilder: (context, state) => state.extra is FadeIn
      ? CustomTransitionPage(
          key: state.pageKey,
          transitionDuration: const Duration(milliseconds: 400),
          child: build(state),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        )
      : MaterialPage(key: state.pageKey, child: build(state)),
);
