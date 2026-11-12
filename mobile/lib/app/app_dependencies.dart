import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/token_storage.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/config_repository.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/play_repository.dart';
import '../data/repositories/squad_repository.dart';
import '../data/repositories/support_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/venue_repository.dart';
import 'session/app_cubit.dart';

/// Builds the object graph once per app start: config → storage → API client → repositories → AppCubit.
class AppDependencies {
  final AppConfig config;
  final TokenStorage tokens;
  final AppPreferences preferences;
  final ApiClient api;

  final AuthRepository auth;
  final UserRepository users;
  final ConfigRepository appConfig;
  final LocationRepository locations;
  final VenueRepository venues;
  final BookingRepository bookings;
  final NotificationRepository notifications;
  final SupportRepository support;
  final PlayRepository play;
  final SquadRepository squad;

  late final AppCubit appCubit = AppCubit(tokens: tokens, prefs: preferences, configRepository: appConfig, userRepository: users);

  AppDependencies._(this.config, this.tokens, this.preferences, this.api)
    : auth = AuthRepository(api),
      users = UserRepository(api),
      appConfig = ConfigRepository(api),
      locations = LocationRepository(api),
      venues = VenueRepository(api),
      bookings = BookingRepository(api),
      notifications = NotificationRepository(api),
      support = SupportRepository(api),
      play = PlayRepository(api),
      squad = SquadRepository(api);

  factory AppDependencies(AppConfig config) {
    final tokens = TokenStorage();
    return AppDependencies._(config, tokens, AppPreferences(), ApiClient(config: config, tokens: tokens));
  }
}
