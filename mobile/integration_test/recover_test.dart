// The backend starts AFTER the app launched: "Try again" on Create must recover.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/app/app_dependencies.dart';
import 'package:turflet/app/app_scope.dart';
import 'package:turflet/core/config/app_config.dart';
import 'package:turflet/features/play/view/create_screen.dart';
import 'package:turflet/core/theme/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('create screen recovers when the server comes up', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deps = AppDependencies(AppConfig.fromDartDefine());
    final state = deps.appCubit;
    await state.boot();
    // ignore: avoid_print
    print('SPORTS AT LAUNCH: ${state.state.sports.length}');
    await tester.pumpWidget(
      AppScope(
        deps: deps,
        child: MaterialApp(
          theme: buildTheme(),
          home: const CreateScreen(type: 'match'),
        ),
      ),
    );
    for (var i = 0; i < 90 && find.text('Quick match').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('Try again').evaluate().isNotEmpty && i % 6 == 0) await tester.tap(find.text('Try again'));
    }
    // ignore: avoid_print
    print('RECOVERED: ${find.text('Quick match').evaluate().isNotEmpty} · sports now ${state.state.sports.length}');
    await tester.tap(find.text('Tournament'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Quick match'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
