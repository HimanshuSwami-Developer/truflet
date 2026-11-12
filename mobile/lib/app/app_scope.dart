import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/config_repository.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/support_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/venue_repository.dart';
import 'app_dependencies.dart';

/// Makes every repository and the app-wide [AppCubit] available below [child].
/// Screens build their own cubits from these with `context.read<…>()`.
class AppScope extends StatelessWidget {
  final AppDependencies deps;
  final Widget child;
  const AppScope({super.key, required this.deps, required this.child});

  @override
  Widget build(BuildContext context) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AuthRepository>.value(value: deps.auth),
      RepositoryProvider<UserRepository>.value(value: deps.users),
      RepositoryProvider<ConfigRepository>.value(value: deps.appConfig),
      RepositoryProvider<LocationRepository>.value(value: deps.locations),
      RepositoryProvider<VenueRepository>.value(value: deps.venues),
      RepositoryProvider<BookingRepository>.value(value: deps.bookings),
      RepositoryProvider<NotificationRepository>.value(value: deps.notifications),
      RepositoryProvider<SupportRepository>.value(value: deps.support),
    ],
    child: BlocProvider.value(value: deps.appCubit, child: child),
  );
}
