// The backend starts AFTER the app launched: "Try again" on Create must recover.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/screens/create.dart';
import 'package:turflet/state.dart';
import 'package:turflet/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('create screen recovers when the server comes up', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.boot();
    // ignore: avoid_print
    print('SPORTS AT LAUNCH: ${state.sports.length}');
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(theme: buildTheme(), home: const CreateScreen(type: 'match')),
    ));
    for (var i = 0; i < 90 && find.text('Quick match').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Try again').evaluate().isNotEmpty && i % 6 == 0) await tester.tap(find.text('Try again'));
    }
    // ignore: avoid_print
    print('RECOVERED: ${find.text('Quick match').evaluate().isNotEmpty} · sports now ${state.sports.length}');
    await tester.tap(find.text('Tournament'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Quick match'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
