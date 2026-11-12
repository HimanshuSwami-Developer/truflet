import 'bootstrap.dart';
import 'core/config/app_config.dart';

/// Single entry point. The backend is chosen with `--dart-define=APP_ENV=local|stage|prod` (default: local).
void main() => bootstrap(AppConfig.fromDartDefine());
