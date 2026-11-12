import 'dart:io';

/// Where the app talks to.
///
/// Pick one at build time with `--dart-define=APP_ENV=local|stage|prod`:
///   flutter run                               → local
///   flutter run --dart-define=APP_ENV=stage   → stage
///   flutter run --dart-define=APP_ENV=prod    → prod
enum AppEnvironment {
  local,
  stage,
  prod;

  static AppEnvironment fromName(String name) =>
      AppEnvironment.values.firstWhere((e) => e.name == name, orElse: () => AppEnvironment.prod);
}

class AppConfig {
  final AppEnvironment environment;

  /// Base URL of the Django API, including the `/api/v1` prefix.
  final String apiBaseUrl;

  /// Prints request/response lines to the debug console (never tokens or bodies).
  final bool logNetwork;

  const AppConfig({required this.environment, required this.apiBaseUrl, required this.logNetwork});

  static const _prodApi = 'https://truflet.vercel.app/api/v1';
  static const _stageApi = String.fromEnvironment('STAGE_API_BASE', defaultValue: 'https://truflet-stage.vercel.app/api/v1');

  /// `--dart-define=API_BASE=...` overrides the URL for any environment (used by the offline tests).
  static const _apiOverride = String.fromEnvironment('API_BASE');

  factory AppConfig.of(AppEnvironment env) {
    final url = _apiOverride.isNotEmpty
        ? _apiOverride
        : switch (env) {
            // Android emulators reach the host machine on 10.0.2.2.
            AppEnvironment.local => Platform.isAndroid ? 'http://10.0.2.2:8000/api/v1' : 'http://127.0.0.1:8000/api/v1',
            AppEnvironment.stage => _stageApi,
            AppEnvironment.prod => _prodApi,
          };
    return AppConfig(environment: env, apiBaseUrl: url, logNetwork: env != AppEnvironment.prod);
  }

  /// Environment from `--dart-define=APP_ENV=local|stage|prod` (defaults to local).
  factory AppConfig.fromDartDefine() => AppConfig.of(AppEnvironment.fromName(const String.fromEnvironment('APP_ENV')));
}
