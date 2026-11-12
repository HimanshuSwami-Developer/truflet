// Regression test: app launched while the backend is unreachable must not crash (main tabs render).
//   flutter test integration_test/offline_test.dart -d <device> --dart-define=API_BASE=http://127.0.0.1:8999/api/v1
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turflet/app/app_dependencies.dart';
import 'package:turflet/app/app_scope.dart';
import 'package:turflet/core/config/app_config.dart';
import 'package:turflet/features/shell/view/main_shell.dart';
import 'package:turflet/core/theme/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('offline launch does not crash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deps = AppDependencies(AppConfig.fromDartDefine());
    final state = deps.appCubit;
    await state.boot(); // fails quietly: server unreachable
    expect(state.state.sports, isEmpty);

    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await tester.pumpWidget(
      AppScope(
        deps: deps,
        child: MaterialApp(key: UniqueKey(), theme: buildTheme(), home: const MainShell()),
      ),
    );
    await settle();

    FlutterError.onError = original;
    // ignore: avoid_print
    print('OFFLINE ERRORS: ${errors.length} ${errors.toSet()}');
    expect(errors, isEmpty);
  });
}
