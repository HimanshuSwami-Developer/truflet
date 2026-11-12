import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/theme.dart';
import 'app_dependencies.dart';
import 'app_scope.dart';
import 'router/app_router.dart';

class TurfletApp extends StatefulWidget {
  final AppDependencies deps;
  const TurfletApp({super.key, required this.deps});

  @override
  State<TurfletApp> createState() => _TurfletAppState();
}

class _TurfletAppState extends State<TurfletApp> {
  late final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    deps: widget.deps,
    child: MaterialApp.router(
      title: 'Turflet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Splash plays every launch, then routes: onboarding (first launch only) → location → home.
      routerConfig: _router,
    ),
  );
}
