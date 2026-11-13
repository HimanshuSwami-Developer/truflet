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
  await deps.push.init();
  await deps.appCubit.boot();
  // push token follows the session: registered on sign-in, removed on sign-out
  deps.push.setSignedIn(deps.appCubit.loggedIn);
  deps.appCubit.stream.listen((_) => deps.push.setSignedIn(deps.appCubit.loggedIn));
  runApp(TurfletApp(deps: deps));
}
