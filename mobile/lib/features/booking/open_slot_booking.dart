import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/router/app_navigation.dart';
import '../../app/router/app_routes.dart';
import '../../core/network/json.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repositories/venue_repository.dart';

/// Fetches the venue, then opens the slot picker ("Book again", "Book" on Saved, reschedule, …).
Future<void> openSlotBooking(
  BuildContext context,
  int venueId, {
  int? sportId,
  Json? reschedule,
  DateTime? date,
  int? startHour,
}) async {
  try {
    final v = await context.read<VenueRepository>().details(venueId);
    if (context.mounted) {
      await context.pushSlotBooking(
        SlotBookingArgs(venue: v, initialSportId: sportId, reschedule: reschedule, initialDate: date, initialStart: startHour),
      );
    }
  } catch (e) {
    if (context.mounted) toast(context, e.toString());
  }
}
