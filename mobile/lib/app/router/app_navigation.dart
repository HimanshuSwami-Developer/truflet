import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/json.dart';
import '../session/app_cubit.dart';
import 'app_routes.dart';

/// Typed navigation used by screens: `context.pushVenue(id)`, `context.goTab(1)`, …
extension AppNavigation on BuildContext {
  // ------------------------------------------------------------ onboarding flow (replaces the stack)
  void goOnboarding() => go(AppRoutes.onboarding, extra: const FadeIn());
  void goFirstLocation({bool fade = false}) => go('${AppRoutes.location}?first=1', extra: fade ? const FadeIn() : null);
  void goHome({bool fade = false}) => go(AppRoutes.home, extra: fade ? const FadeIn() : null);

  // ------------------------------------------------------------ pushed screens
  /// Resolves to true once the player is signed in.
  Future<bool?> pushLogin() => push<bool>(AppRoutes.login);

  /// Resolves to true when a new area was picked.
  Future<bool?> pushLocation() => push<bool>(AppRoutes.location);

  Future<void> pushNotifications() => push(AppRoutes.notifications);
  Future<void> pushSaved() => push(AppRoutes.saved);
  Future<void> pushHelp({Json? booking}) => push(AppRoutes.help, extra: booking);
  Future<void> pushPolicy({int tab = 0}) => push('${AppRoutes.policy}?tab=$tab');
  Future<void> pushVenue(int venueId) => push(AppRoutes.venueOf(venueId));

  /// Resolves to true after a successful reschedule.
  Future<bool?> pushSlotBooking(SlotBookingArgs args) => push<bool>(AppRoutes.slotBooking, extra: args);
  Future<void> pushPayment(Json booking) => push(AppRoutes.payment, extra: booking);
  Future<void> pushTicket(int bookingId) => push(AppRoutes.ticketOf(bookingId));
  Future<void> pushCreate(String type) => push('${AppRoutes.create}?type=$type');
  Future<void> pushTournament(int id) => push(AppRoutes.tournamentOf(id));
  Future<void> pushGroup(int id) => push(AppRoutes.groupOf(id));

  // ------------------------------------------------------------ replace the current screen
  Future<void> replaceWithBookingConfirmed(Json booking) => _replace(AppRoutes.bookingConfirmed, extra: booking);
  Future<void> replaceWithTicket(int bookingId) => _replace(AppRoutes.ticketOf(bookingId));
  Future<void> replaceWithTournament(int id) => _replace(AppRoutes.tournamentOf(id));

  /// Like Navigator.pushReplacement: the replaced screen's `push` future resolves (with null)
  /// so the screen underneath can refresh. go_router's pushReplacement alone never resolves it.
  Future<void> _replace(String location, {Object? extra}) {
    final router = GoRouter.of(this);
    final replaced = router.routerDelegate.currentConfiguration.last;
    final next = router.pushReplacement(location, extra: extra);
    if (replaced is ImperativeRouteMatch && !replaced.completer.isCompleted) replaced.complete();
    return next;
  }

  // ------------------------------------------------------------ tabs
  /// Leaves any pushed screens and switches the bottom-nav tab.
  void goTab(int i) {
    read<AppCubit>().setTab(i);
    Navigator.of(this).popUntil((r) => r.isFirst);
  }
}
