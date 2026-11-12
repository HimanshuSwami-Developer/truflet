import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/splash.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  final state = AppState();
  await state.boot();
  runApp(ChangeNotifierProvider.value(value: state, child: const TurfletApp()));
}

class TurfletApp extends StatelessWidget {
  const TurfletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Turflet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Splash plays every launch, then routes: onboarding (first launch only) → location → home.
      home: const SplashScreen(),
    );
  }
}
