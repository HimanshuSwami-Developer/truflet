// Routing smoke tests for the real app (GoRouter + blocs). Network calls fail fast in
// flutter_test, so every screen runs in its offline state — enough to check navigation.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/app/app.dart';
import 'package:turflet/app/app_dependencies.dart';
import 'package:turflet/app/router/app_navigation.dart';
import 'package:turflet/app/router/app_routes.dart';
import 'package:turflet/app/session/app_state.dart';
import 'package:turflet/core/config/app_config.dart';
import 'package:turflet/features/auth/view/sign_in_prompt.dart';
import 'package:turflet/features/booking/view/ticket_screen.dart';
import 'package:turflet/features/lobby/view/lobbies_screen.dart';
import 'package:turflet/features/lobby/view/match_room_screen.dart';
import 'package:turflet/features/lobby/view/request_thread_screen.dart';
import 'package:turflet/features/location/view/location_screen.dart';
import 'package:turflet/features/onboarding/view/onboarding_screen.dart';
import 'package:turflet/features/saved/view/saved_screen.dart';
import 'package:turflet/features/shell/view/main_shell.dart';
import 'package:turflet/features/splash/view/splash_screen.dart';

Future<AppDependencies> _boot(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final deps = AppDependencies(
    const AppConfig(environment: AppEnvironment.local, apiBaseUrl: 'http://127.0.0.1:1/api/v1', logNetwork: false),
  );
  await deps.appCubit.boot();
  return deps;
}

Future<void> _settle(WidgetTester tester, [int ms = 4000]) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('first launch: splash → onboarding → location', (tester) async {
    final deps = await tester.runAsync(() => _boot({}));
    await tester.pumpWidget(TurfletApp(deps: deps!));
    expect(find.byType(SplashScreen), findsOneWidget);

    await _settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50))); // prefs write
    await _settle(tester, 1500);
    expect(find.byType(LocationScreen), findsOneWidget);
    expect(deps.appCubit.state.onboarded, isTrue);
  });

  testWidgets('returning player goes straight to the tabs; account tabs are gated', (tester) async {
    final deps = await tester.runAsync(() => _boot({'onboarded': true, 'areaId': 1, 'areaName': 'HSR', 'cityName': 'Bengaluru'}));
    await tester.pumpWidget(TurfletApp(deps: deps!));
    await _settle(tester);
    expect(find.byType(MainShell), findsOneWidget);

    await tester.tap(find.text('Matches'));
    await _settle(tester, 500);
    expect(deps.appCubit.state.tab, AppTab.matches);
    expect(find.byType(SignInPrompt), findsOneWidget);

    await tester.tap(find.text('Bookings'));
    await _settle(tester, 500);
    expect(deps.appCubit.state.tab, AppTab.bookings);
    expect(find.byType(SignInPrompt), findsOneWidget);
  });

  testWidgets('replace resolves the replaced screen\'s push future, goTab pops to the shell', (tester) async {
    final deps = await tester.runAsync(() => _boot({'onboarded': true, 'areaId': 1, 'areaName': 'HSR', 'cityName': 'Bengaluru'}));
    await tester.pumpWidget(TurfletApp(deps: deps!));
    await _settle(tester);

    var savedClosed = false;
    tester.element(find.byType(MainShell)).pushSaved().then((_) => savedClosed = true);
    await _settle(tester, 1000);
    expect(find.byType(SavedScreen), findsOneWidget);

    tester.element(find.byType(SavedScreen)).replaceWithTicket(42);
    await _settle(tester, 1000);
    expect(find.byType(TicketScreen), findsOneWidget);
    expect(find.byType(SavedScreen), findsNothing);
    expect(savedClosed, isTrue, reason: 'like Navigator.pushReplacement, the replaced route completes');

    tester.element(find.byType(TicketScreen)).goTab(AppTab.profile);
    await _settle(tester, 1000);
    expect(find.byType(TicketScreen), findsNothing);
    expect(deps.appCubit.state.tab, AppTab.profile);
  });

  testWidgets('match screens open from their routes (offline → error state, no crash)', (tester) async {
    final deps = await tester.runAsync(() => _boot({'onboarded': true, 'areaId': 1, 'areaName': 'HSR', 'cityName': 'Bengaluru'}));
    await tester.pumpWidget(TurfletApp(deps: deps!));
    await _settle(tester);
    final shell = tester.element(find.byType(MainShell));

    shell.pushMatch(7);
    await _settle(tester, 1500);
    expect(find.byType(MatchRoomScreen), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    tester.element(find.byType(MatchRoomScreen)).replaceWithRequestThread(7, 3);
    await _settle(tester, 1500);
    expect(find.byType(RequestThreadScreen), findsOneWidget);

    tester.element(find.byType(RequestThreadScreen)).goTab(AppTab.explore);
    await _settle(tester, 1000);
    shell.pushLobbies(const LobbiesArgs(areaId: 1, cityName: 'Bengaluru'));
    await _settle(tester, 1500);
    expect(find.byType(LobbiesScreen), findsOneWidget);
    expect(find.text('Open lobbies in Bengaluru'), findsOneWidget);
  });
}
