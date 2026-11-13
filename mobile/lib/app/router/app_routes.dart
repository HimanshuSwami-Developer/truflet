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
  static const lobbies = '/lobbies'; // extra: LobbiesArgs
  static const squad = '/squad'; // extra: SquadArgs
  static const match = '/matches/:lobbyId';
  static const requestThread = '/matches/:lobbyId/requests/:requestId';

  static String venueOf(int id) => '/venues/$id';
  static String ticketOf(int bookingId) => '/tickets/$bookingId';
  static String matchOf(int lobbyId) => '/matches/$lobbyId';
  static String requestOf(int lobbyId, int requestId) => '/matches/$lobbyId/requests/$requestId';
}

/// Arguments for the Venue & Slot Matrix (new match or reschedule).
class SlotBookingArgs {
  final Json venue;
  final int? initialSportId;
  final Json? reschedule;
  final DateTime? initialDate;
  final int? initialStart;
  const SlotBookingArgs({required this.venue, this.initialSportId, this.reschedule, this.initialDate, this.initialStart});
}

/// Open Lobbies (Solo view): one slot at a venue, every lobby at a venue, or the city board.
class LobbiesArgs {
  final Json? venue;
  final int? sportId, courtId, startHour;
  final String? date;

  /// Shown under the title, e.g. "Sat, 15 Nov · 7 PM · Pitch 1".
  final String subtitle;

  /// City board: lobbies anywhere in the city of this area.
  final int? areaId;
  final String cityName;
  const LobbiesArgs({
    this.venue,
    this.sportId,
    this.courtId,
    this.startHour,
    this.date,
    this.subtitle = '',
    this.areaId,
    this.cityName = '',
  });

  bool get isCity => venue == null;
}

/// Squad Builder: the slot the host picked on the matrix.
class SquadArgs {
  final Json venue;
  final Json sport; // venue_sports entry: {sport_id, name, max_players, ...}
  final Json court;
  final DateTime date;
  final int startHour, duration;

  /// Slot rent for the whole squad (₹).
  final int turfPrice;
  const SquadArgs({
    required this.venue,
    required this.sport,
    required this.court,
    required this.date,
    required this.startHour,
    required this.duration,
    required this.turfPrice,
  });
}

/// Pass as `extra` to open a route with the splash cross-fade instead of the platform slide.
class FadeIn {
  const FadeIn();
}
