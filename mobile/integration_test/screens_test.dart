// UI audit: opens every screen (plus tabs, sheets and wizard steps) against the
// local backend at several phone sizes, and reports every layout overflow or
// exception. Screenshots are written to SHOT_DIR when given.
//
//   flutter test integration_test/screens_test.dart -d <simulator> \
//     --dart-define=SHOT_DIR=/absolute/path
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/app/app_dependencies.dart';
import 'package:turflet/app/app_scope.dart';
import 'package:turflet/app/session/app_state.dart';
import 'package:turflet/app/router/app_routes.dart';
import 'package:turflet/core/config/app_config.dart';
import 'package:turflet/core/network/json.dart';
import 'package:turflet/core/theme/theme.dart';
import 'package:turflet/features/auth/view/login_screen.dart';
import 'package:turflet/features/auth/view/profile_form.dart';
import 'package:turflet/features/booking/view/booking_confirmed_screen.dart';
import 'package:turflet/features/booking/view/payment_screen.dart';
import 'package:turflet/features/booking/view/slot_booking_screen.dart';
import 'package:turflet/features/booking/view/ticket_screen.dart';
import 'package:turflet/features/location/view/location_screen.dart';
import 'package:turflet/features/notifications/view/notifications_screen.dart';
import 'package:turflet/features/onboarding/view/onboarding_screen.dart';
import 'package:turflet/features/saved/view/saved_screen.dart';
import 'package:turflet/features/shell/view/main_shell.dart';
import 'package:turflet/features/splash/view/splash_screen.dart';
import 'package:turflet/features/support/view/help_screen.dart';
import 'package:turflet/features/support/view/policy_screen.dart';
import 'package:turflet/features/venue/view/venue_details_screen.dart';

const shotDir = String.fromEnvironment('SHOT_DIR');
// Optional filters, e.g. --dart-define=ONLY=16 --dart-define=SIZE=small
const only = String.fromEnvironment('ONLY');
const onlySize = String.fromEnvironment('SIZE');

class Size3 {
  final String name;
  final double w, h, top, bottom;
  const Size3(this.name, this.w, this.h, this.top, this.bottom);
}

const sizes = [
  Size3('small-360x690', 360, 690, 24, 0),
  Size3('iphone-390x844', 390, 844, 47, 34),
  Size3('max-430x932', 430, 932, 59, 34),
];

final problems = <String>[];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('audit every screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deps = AppDependencies(AppConfig.fromDartDefine());
    final api = deps.api;
    final state = deps.appCubit;
    await state.boot();
    await api.post('/auth/otp/request/', {'email': 'arjun@turflet.app'}).catchError((_) => null);
    final login = asMap(await api.post('/auth/otp/verify/', {'email': 'arjun@turflet.app', 'code': '123456'}));
    await state.setLoggedIn(login);
    final cities = asList(await api.get('/cities/'));
    final area = asList(cities.first['areas']).first;
    await state.setArea(id: area['id'], area: area['name'], city: cities.first['name'], lat: area['lat'], lng: area['lng']);

    final venues = asList(await api.get('/venues/', {'area': area['id']}));
    final gf = venues.firstWhere((v) => v['name'] == 'Greenfield Sports Arena');
    final venue = asMap(await api.get('/venues/${gf['id']}/'));
    final upcoming = asList(asMap(await api.get('/bookings/', {'tab': 'upcoming'}))['items']);
    final ticketId = upcoming.first['id'] as int;
    final day = DateTime.now().add(const Duration(days: 5));
    final ds = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final hold = asMap(
      await api.post('/bookings/', {
        'venue': gf['id'],
        'court': asList(venue['courts']).last['id'],
        'sport': asList(venue['venue_sports']).first['sport_id'],
        'date': ds,
        'start_hour': 9,
        'duration': 2,
      }),
    );

    Future<void> settle([int frames = 14]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final shotKey = GlobalKey();
    var current = '';

    Future<void> shot(String name) async {
      if (shotDir.isEmpty) return;
      final boundary = shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$shotDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> open(String name, Widget page, Size3 s, {Future<void> Function()? then}) async {
      if (only.isNotEmpty && !name.startsWith(only)) return;
      current = '${s.name} · $name';
      await tester.pumpWidget(
        AppScope(
          deps: deps,
          child: RepaintBoundary(
            key: shotKey,
            // UniqueKey: never reuse the previous screen's State
            child: MaterialApp(key: UniqueKey(), theme: buildTheme(), debugShowCheckedModeBanner: false, home: page),
          ),
        ),
      );
      await settle();
      await shot('${s.name}__$name');
      if (then != null) await then();
    }

    Future<void> tapText(String text, String shotName, Size3 s) async {
      var f = find.text(text);
      if (f.evaluate().isEmpty && find.byType(Scrollable).evaluate().isNotEmpty) {
        try {
          await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 15);
        } catch (_) {}
        f = find.text(text);
      }
      if (f.evaluate().isEmpty) {
        problems.add('${s.name} · $shotName: could not find "$text" to tap');
        return;
      }
      current = '${s.name} · $shotName';
      await tester.ensureVisible(f.first);
      await tester.pump();
      // ignore: avoid_print
      print("TAP $shotName at ${tester.getCenter(f.first)}");
      await tester.tap(f.first);
      await settle(10);
      await shot('${s.name}__$shotName');
    }

    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString().split('\n').first;
      final where = details.informationCollector
          ?.call()
          .map((e) => e.toString())
          .firstWhere((l) => l.contains('lib/'), orElse: () => '');
      problems.add('$current: $msg ${where ?? ''}');
    };

    for (final s in sizes.where((x) => onlySize.isEmpty || x.name.startsWith(onlySize))) {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = Size(s.w * 3, s.h * 3);
      tester.view.padding = FakeViewPadding(top: s.top * 3, bottom: s.bottom * 3);
      tester.view.viewPadding = FakeViewPadding(top: s.top * 3, bottom: s.bottom * 3);

      await open('01-splash', const SplashScreen(), s);
      await open(
        '02-onboarding',
        const OnboardingScreen(),
        s,
        then: () async {
          await tapText('Next', '02b-onboarding-2', s);
          await tapText('Next', '02c-onboarding-3', s);
        },
      );
      await open('03-location', const LocationScreen(first: true), s);
      await open('03b-login', const LoginScreen(), s);
      for (var tab = 0; tab < 3; tab++) {
        state.setTab(tab);
        await open(
          'tab$tab',
          const MainShell(),
          s,
          then: () async {
            if (tab == AppTab.bookings) {
              await tapText('Completed', 'tab1b-completed', s);
              await tapText('Cancelled', 'tab1c-cancelled', s);
            }
            if (tab == AppTab.profile) await tapText('Edit profile', 'tab2b-editing', s);
          },
        );
      }
      state.setTab(AppTab.explore);
      await open('05-details', VenueDetailsScreen(venueId: gf['id']), s);
      await open('06-booking', SlotBookingScreen(args: SlotBookingArgs(venue: venue)), s);
      await open('07-payment', PaymentScreen(booking: hold), s);
      await open('08-success', BookingConfirmedScreen(booking: upcoming.first), s);
      await open(
        '10-ticket',
        TicketScreen(bookingId: ticketId),
        s,
        then: () async {
          await tapText('Cancel booking', '10b-cancel-sheet', s);
        },
      );
      await open('11-saved', const SavedScreen(), s);
      await open('12-help', const HelpScreen(), s);
      await open(
        '13-policy',
        const PolicyScreen(),
        s,
        then: () async {
          await tapText('Privacy', '13b-privacy', s);
          await tapText('Terms', '13c-terms', s);
        },
      );
      await open('13d-notifications', const NotificationsScreen(), s);
      await open(
        '19-profile-form',
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ProfileForm(submitLabel: 'Save & continue', showHandle: true, onSaved: () {}),
            ),
          ),
        ),
        s,
        then: () async {
          await tester.enterText(find.byType(TextField).first, '');
          await tapText('Save & continue', '19b-profile-form-errors', s);
        },
      );
      state.setTab(AppTab.profile);
      await open(
        '19c-profile-sheet',
        const MainShell(),
        s,
        then: () async {
          await tapText('Edit', '19d-edit-details-sheet', s);
        },
      );
      state.setTab(AppTab.explore);
    }

    FlutterError.onError = original;
    tester.view.reset();
    await api.post('/bookings/${hold['id']}/cancel/', {}).catchError((_) => null);

    // ignore: avoid_print
    print('=== UI AUDIT: ${problems.length} problem(s) ===');
    for (final p in problems.toSet()) {
      // ignore: avoid_print
      print('PROBLEM $p');
    }
  });
}
