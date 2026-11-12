// Regression test: app launched while the backend is unreachable must not crash.
//   flutter test integration_test/offline_test.dart -d <device> --dart-define=API_BASE=http://127.0.0.1:8999/api/v1
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/screens/create.dart';
import 'package:turflet/screens/shell.dart';
import 'package:turflet/state.dart';
import 'package:turflet/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('offline launch does not crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.boot(); // fails quietly: server unreachable
    expect(state.sports, isEmpty);

    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    for (final type in ['match', 'tour']) {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(key: UniqueKey(), theme: buildTheme(), home: CreateScreen(type: type)),
      ));
      await settle();
      expect(find.text('Try again'), findsOneWidget, reason: 'Create($type) should offer a retry');
      await tester.tap(find.text('Try again'));
      await settle();
    }

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(key: UniqueKey(), theme: buildTheme(), home: const MainShell()),
    ));
    await settle();

    FlutterError.onError = original;
    // ignore: avoid_print
    print('OFFLINE ERRORS: ${errors.length} ${errors.toSet()}');
    expect(errors, isEmpty);
  });
}
