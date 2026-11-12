import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/json.dart';

/// Opens Google Maps at the venue (coordinates when known, else a text search).
Future<void> openMaps(dynamic lat, dynamic lng, String label) async {
  final uri = lat != null
      ? Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng')
      : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(label)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Google Calendar "add event" link for a booking.
Future<void> addToCalendar(Json b) async {
  final d = DateTime.parse(b['date']);
  final s = DateTime(d.year, d.month, d.day, b['start_hour']);
  final e = s.add(Duration(hours: b['duration']));
  String f(DateTime x) =>
      '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}T${x.hour.toString().padLeft(2, '0')}0000';
  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': '${b['sport']['name']} at ${b['venue']['name']}',
    'dates': '${f(s)}/${f(e)}',
    'details': 'Turflet booking ${b['code']} · ${b['court']['name']}',
    'location': b['venue']['address'] ?? '',
  });
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void inviteTeam(Json b) => SharePlus.instance.share(
  ShareParams(
    text:
        "I've booked ${b['sport']['name']} at ${b['venue']['name']} on ${b['date_label']}, ${b['time_short']} "
        '(${b['court']['name']}). Join me! Booking ${b['code']}',
  ),
);
