import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'booking.dart';
import 'details.dart';
import 'help.dart';
import 'policy.dart';

/// 10 · Ticket (full QR pass) with cancel / reschedule
class TicketScreen extends StatefulWidget {
  final int bookingId;
  const TicketScreen({super.key, required this.bookingId});
  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  final key = GlobalKey<State>();
  int version = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Loader<Json>(
          key: ValueKey(version),
          load: () async => asMap(await api.get('/bookings/${widget.bookingId}/')),
          builder: (context, b, reload) => _body(b, reload),
        ),
      );

  Future<void> _cancel(Json b) async {
    Json quote;
    try {
      quote = asMap(await api.get('/bookings/${b['id']}/cancel/'));
    } catch (e) {
      if (mounted) toast(context, e.toString());
      return;
    }
    if (!mounted) return;
    var done = false;
    Json? result;
    var busy = false;
    await sheet(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          if (done) {
            return Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: C.orangeSoft, shape: BoxShape.circle),
                child: const Icon(LucideIcons.check, color: C.orangeInk),
              ),
              const SizedBox(height: 12),
              Text('Booking cancelled', style: d(22)),
              const SizedBox(height: 12),
              Text(
                  'Cancellation ID ${result?['cancellation_code']}. '
                  '${(result?['refund_amount'] ?? 0) > 0 ? '${inr(result?['refund_amount'])} will be refunded to your ${result?['payment_method_label']}.' : 'A confirmation has been sent by SMS.'}',
                  textAlign: TextAlign.center,
                  style: t(14, c: C.muted, h: 1.5)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton('Back to my bookings', height: 52, radius: 16, shadow: false, fontSize: 15, onTap: () {
                  Navigator.pop(ctx);
                  goTab(context, 1);
                }),
              ),
            ]);
          }
          final pct = quote['percent'];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Cancel this booking?', style: d(22)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                PriceRow('Amount paid', inr(quote['amount_paid'])),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('Cancellation charge ($pct% refund)', style: t(14, c: C.muted))),
                  Text('−${inr(quote['charge'])}', style: t(14, c: C.orange)),
                ]),
                const SizedBox(height: 8),
                PriceRow('Refund', inr(quote['refund']), bold: true, top: true),
              ]),
            ),
            const SizedBox(height: 14),
            Text('Tip: rescheduling is free once. The venue can then release this slot to other players.',
                style: t(13, c: C.muted, h: 1.5)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: PrimaryButton('Keep booking', height: 52, radius: 16, shadow: false, fontSize: 15, onTap: () => Navigator.pop(ctx))),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(busy ? 'Cancelling…' : 'Cancel anyway', fg: C.orangeInk, bg: C.orangeBg, border: const Color(0xFFFED7AA),
                    fontSize: 15, onTap: busy
                        ? null
                        : () async {
                            set(() => busy = true);
                            try {
                              result = asMap(await api.post('/bookings/${b['id']}/cancel/', {}));
                              set(() => done = true);
                            } catch (e) {
                              set(() => busy = false);
                              if (ctx.mounted) toast(ctx, e.toString());
                            }
                          }),
              ),
            ]),
          ]);
        }));
    if (done && mounted) setState(() => version++);
  }

  Widget _body(Json b, Future<void> Function() reload) {
    final top = MediaQuery.of(context).padding.top;
    final status = b['status'] as String;
    final confirmed = status == 'confirmed';
    final hoursLeft = (b['hours_left'] as num).toDouble();
    final statusLabel = {
      'confirmed': 'CONFIRMED',
      'completed': 'COMPLETED',
      'cancelled': 'CANCELLED',
      'held': 'AWAITING PAYMENT',
      'expired': 'EXPIRED'
    }[status]!;
    return ListView(padding: EdgeInsets.fromLTRB(0, top + 8, 0, 32), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(children: [
          const BackSquare(),
          const SizedBox(width: 12),
          Expanded(child: Text('Your ticket', style: d(20))),
          SquareIconButton(LucideIcons.share2, iconSize: 18, label: 'Share ticket', onTap: () {
            SharePlus.instance.share(ShareParams(
                text: 'Turflet booking ${b['code']} · ${b['venue']['name']} · ${b['date_long']} ${b['time_long']} · ${b['court']['name']}'));
          }),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: shadowBig),
        child: Column(children: [
          SizedBox(
            height: 120,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: Stack(fit: StackFit.expand, children: [
                Img(b['venue']['image']),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.1, 1], colors: [Color(0x0D000000), Color(0xB3000000)]),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['venue']['name'], style: d(19, c: Colors.white)),
                        Text(b['venue']['address'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t(12, c: Colors.white)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Pill(statusLabel, bg: confirmed ? C.lime : Colors.white, fg: C.ink),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(children: [
              Opacity(
                opacity: confirmed ? 1 : 0.35,
                child: Container(
                  width: 196,
                  height: 196,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line, width: 2)),
                  child: QrImageView(
                    data: b['qr_payload'],
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: C.ink),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: C.ink),
                    semanticsLabel: 'Entry QR code containing booking ID, venue, court, date, time, players and payment status',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(b['code'], style: d(18, ls: 1)),
              const SizedBox(height: 10),
              Text('Show this QR at the venue counter. One scan\nverifies your full booking — no login needed.',
                  textAlign: TextAlign.center, style: t(12, c: C.muted, h: 1.5)),
              const SizedBox(height: 14),
              Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                for (final x in ['Booking ID', 'Venue & court', 'Date & slot', 'Players', 'Payment status'])
                  Pill(x, bg: C.chip, fg: C.mutedInk, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4)),
              ]),
            ]),
          ),
          const Perforation(height: 26, notch: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(children: [
              _pair(KV('Sport', b['sport']['name'], vColor: hex(b['sport']['fg'])),
                  KV('Court', '${b['court']['name']}${(b['court']['meta'] ?? '').isNotEmpty ? ' · ${b['court']['meta']}' : ''}')),
              _pair(KV('Date', b['date_long']), KV('Time', b['time_long'])),
              _pair(KV('Duration', '${b['duration']} hour${b['duration'] == 1 ? '' : 's'}'), KV('Players', 'Up to ${b['players']}')),
              _pair(KV('Booked on', b['paid_at'] ?? '—'), (b['masked_phone'] ?? '').toString().isNotEmpty ? KV('Mobile', b['masked_phone']) : KV('Email', b['masked_email'] ?? '')),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Expanded(
            child: GhostButton('Directions', icon: LucideIcons.navigation, height: 50, bg: C.blueSoft, fg: C.blue, border: Colors.transparent,
                onTap: () => openMaps(b['venue']['lat'], b['venue']['lng'], '${b['venue']['name']} ${b['venue']['address']}')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GhostButton('Call venue', icon: LucideIcons.phone, height: 50, bg: C.mint, fg: C.green700, border: Colors.transparent,
                onTap: () => launchUrl(Uri(scheme: 'tel', path: b['venue']['phone'] ?? ''))),
          ),
        ]),
      ),
      CardBox(
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const H2('Payment', size: 16),
          const SizedBox(height: 12),
          PriceRow('Slot charges (${b['duration']} × ${inr(b['rate'])})', inr(b['slot_amount'])),
          const SizedBox(height: 10),
          PriceRow('Convenience fee + GST', inr((b['convenience_fee'] ?? 0) + (b['gst'] ?? 0))),
          if ((b['discount'] ?? 0) > 0) ...[
            const SizedBox(height: 10),
            PriceRow('Coupon ${b['coupon']}', '−${inr(b['discount'])}', color: C.brand),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
            child: Row(children: [
              Expanded(
                  child: Text(b['payment_method_label'].toString().isEmpty ? 'Total' : 'Paid via ${b['payment_method_label']}',
                      style: t(14, w: FontWeight.w700))),
              Text(inr(b['total']), style: t(14, w: FontWeight.w700)),
            ]),
          ),
          if ((b['transaction_id'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Transaction ID: ${b['transaction_id']}', style: t(12, c: C.muted)),
          ],
          if (status == 'cancelled') ...[
            const SizedBox(height: 10),
            Text('Cancelled · ${b['cancellation_code']} · refund ${inr(b['refund_amount'])}', style: t(12, w: FontWeight.w600, c: C.orangeInk)),
          ],
        ]),
      ),
      if (confirmed)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.orangeBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.orangeSoft)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: H2('Cancellation', size: 16, color: C.orangeInk)),
              GestureDetector(
                onTap: () => push(context, const PolicyScreen()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Refund policy', style: t(13, w: FontWeight.w600, c: C.orangeInk, deco: TextDecoration.underline)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
                hoursLeft < 6
                    ? 'Your slot starts in under 6 hours, so cancelling now is not refundable. You can still reschedule once for free up to 2 hours before.'
                    : hoursLeft < 24
                        ? 'Cancel now for a 50% refund of slot charges, or reschedule once for free up to 2 hours before.'
                        : 'Cancel now for a full refund of slot charges. You can also reschedule once for free.',
                style: t(13, c: C.orangeDeep, h: 1.5)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GhostButton('Reschedule', height: 46, radius: 14, fg: C.orangeInk, border: const Color(0xFFFED7AA),
                    onTap: (b['reschedule_count'] ?? 0) >= 1 || hoursLeft < 2
                        ? () => toast(context, 'Free reschedule is used up or the slot is too close.')
                        : () async {
                            await BookingScreen.openForVenueId(context, b['venue']['id'], reschedule: b);
                            setState(() => version++);
                          }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton('Cancel booking', height: 46, radius: 14, fg: Colors.white, bg: C.orange, border: Colors.transparent,
                    onTap: () => _cancel(b)),
              ),
            ]),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: GhostButton('Need help with this booking?', icon: LucideIcons.circleHelp,
            onTap: () => push(context, HelpScreen(booking: b))),
      ),
    ]);
  }

  Widget _pair(Widget a, Widget b) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
      );
}
