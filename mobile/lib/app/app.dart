import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/theme.dart';
import 'app_dependencies.dart';
import 'app_scope.dart';
import 'router/app_router.dart';
import 'router/app_routes.dart';

class TurfletApp extends StatefulWidget {
  final AppDependencies deps;
  const TurfletApp({super.key, required this.deps});

  @override
  State<TurfletApp> createState() => _TurfletAppState();
}

class _TurfletAppState extends State<TurfletApp> {
  late final GoRouter _router = createRouter();
  StreamSubscription<void>? _pushTaps;

  @override
  void initState() {
    super.initState();
    // a tapped push opens the notifications list once the home screen is up (splash/onboarding
    // replace the whole stack, so opening it earlier would be lost)
    _pushTaps = widget.deps.push.opens.listen((_) => _openPendingPush());
    _router.routerDelegate.addListener(_openPendingPush);
  }

  void _openPendingPush() {
    if (widget.deps.push.pendingOpen == null) return;
    final stack = _router.routerDelegate.currentConfiguration;
    if (stack.isEmpty || stack.matches.first.matchedLocation != AppRoutes.home) return;
    if (stack.uri.path == AppRoutes.notifications) {
      widget.deps.push.takePendingOpen();
      return;
    }
    widget.deps.push.takePendingOpen();
    WidgetsBinding.instance.addPostFrameCallback((_) => _router.push(AppRoutes.notifications));
  }

  @override
  void dispose() {
    _pushTaps?.cancel();
    _router.routerDelegate.removeListener(_openPendingPush);
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
