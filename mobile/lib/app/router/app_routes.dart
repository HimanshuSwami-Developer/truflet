import '../../core/network/json.dart';

/// Every screen's location. Build paths with the helpers, never by hand.
abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const location = '/location'; // ?first=1 during onboarding
  static const home = '/home'; // bottom-nav shell
  static const login = '/login';
  static const notifications = '/notifications';
  static const saved = '/saved';
  static const help = '/help'; // extra: Json? booking
  static const policy = '/policy'; // ?tab=0|1|2
  static const venue = '/venues/:venueId';
  static const slotBooking = '/book'; // extra: SlotBookingArgs
  static const payment = '/payment'; // extra: Json booking (held)
  static const bookingConfirmed = '/booking-confirmed'; // extra: Json booking (paid)
  static const ticket = '/tickets/:bookingId';
  static const openGames = '/open-games'; // extra: OpenGamesArgs
  static const group = '/groups/:groupId';

  static String venueOf(int id) => '/venues/$id';
  static String ticketOf(int bookingId) => '/tickets/$bookingId';
  static String groupOf(int id) => '/groups/$id';
}

/// Arguments for the slot picker (new booking or reschedule).
/// [group] = play with that group (members get notified); [openGame] = strangers can join.
class SlotBookingArgs {
  final Json venue;
  final int? initialSportId;
  final Json? reschedule;
  final DateTime? initialDate;
  final int? initialStart;
  final Json? group;
  final bool openGame;
  const SlotBookingArgs({
    required this.venue,
    this.initialSportId,
    this.reschedule,
    this.initialDate,
    this.initialStart,
    this.group,
    this.openGame = false,
  });
}

/// Arguments for a venue's open games list.
class OpenGamesArgs {
  final Json venue;
  final int? sportId;
  const OpenGamesArgs({required this.venue, this.sportId});
}

/// Pass as `extra` to open a route with the splash cross-fade instead of the platform slide.
class FadeIn {
  const FadeIn();
}
