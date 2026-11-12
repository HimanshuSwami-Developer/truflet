import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/config/app_config.dart';

/// App start-up: system UI, dependencies, session boot, runApp.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  final deps = AppDependencies(config);
  await deps.appCubit.boot();
  runApp(TurfletApp(deps: deps));
}
