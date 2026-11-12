import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'booking.dart';
import 'help.dart';
import 'policy.dart';
import 'ticket.dart';

/// 9 · My bookings
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

const _tabs = ['upcoming', 'completed', 'cancelled'];

class _BookingsScreenState extends State<BookingsScreen> {
  int tab = 0;
  Json? data;
  String? error;
  int _lastTab = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // refresh whenever the player switches to this tab
    final current = context.watch<AppState>().tab;
    if (current == 1 && _lastTab != 1) _load();
    _lastTab = current;
  }

  Future<void> _load() async {
    try {
      final r = asMap(await api.get('/bookings/', {'tab': _tabs[tab]}));
      if (mounted) {
        setState(() {
        data = r;
        error = null;
      });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _rate(Json b) async {
    var stars = 5;
    final ok = await sheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Rate ${b['venue']['name']}', style: d(20)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 40,
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: C.star),
                  tooltip: '$i stars',
                ),
            ]),
            const SizedBox(height: 16),
            PrimaryButton('Submit', height: 52, onTap: () => Navigator.pop(ctx, true)),
          ]);
        }));
    if (ok != true) return;
    try {
      await api.post('/venues/${b['venue']['id']}/review/', {'rating': stars, 'booking': b['id']});
      if (mounted) toast(context, 'Thanks for rating!');
      _load();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final top = MediaQuery.of(context).padding.top;
    final counts = asMap(data?['counts']);
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(0, top + 12, 0, 20), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My bookings', style: d(28, ls: -0.5)),
                const SizedBox(height: 4),
                Text('Linked to ${s.user?['masked_email'] ?? ''}', style: t(13, c: C.muted)),
              ]),
            ),
            GhostButton('Help', icon: LucideIcons.circleHelp, height: 40, radius: 999, fontSize: 13,
                onTap: () => push(context, const HelpScreen())),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Segmented(
            labels: const ['Upcoming', 'Completed', 'Cancelled'],
            counts: [counts['upcoming'] ?? 0, counts['completed'] ?? 0, counts['cancelled'] ?? 0],
            index: tab,
            onChanged: (i) {
              setState(() => tab = i);
              _load();
            },
          ),
        ),
        const SizedBox(height: 16),
        if (error != null) ErrorRetry(error!, onRetry: _load),
        if (data == null && error == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: C.brand))),
        if (data != null && asList(data!['items']).isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              const Icon(LucideIcons.calendar, size: 40, color: C.muted),
              const SizedBox(height: 12),
              Text(['No upcoming games. Book a slot!', 'No completed games yet.', 'No cancellations.'][tab],
                  style: t(14, c: C.muted), textAlign: TextAlign.center),
              if (tab == 0) ...[
                const SizedBox(height: 16),
                PrimaryButton('Explore turfs', height: 48, onTap: () => s.setTab(0)),
              ],
            ]),
          ),
        for (final b in asList(data?['items'])) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 14), child: _card(b)),
      ]),
    );
  }

  Widget _card(Json b) {
    final status = b['status'];
    final statusStyle = {
      'confirmed': ('Confirmed', C.mint, C.green700),
      'completed': ('Completed', C.chip, C.muted),
      'cancelled': (b['refund_amount'] > 0 ? 'Refunded' : 'Cancelled', C.orangeSoft, C.orangeInk),
    }[status]!;
    final km = b['venue']['area'];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: shadowCard),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () async {
            await push(context, TicketScreen(bookingId: b['id']));
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Img(b['venue']['image'], width: 76, height: 76, radius: BorderRadius.circular(16)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(b['venue']['name'], style: d(16, h: 1.2))),
                    const SizedBox(width: 8),
                    Pill(statusStyle.$1, bg: statusStyle.$2, fg: statusStyle.$3, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
                  ]),
                  const SizedBox(height: 4),
                  Text(km, style: t(13, c: C.muted)),
                  const SizedBox(height: 4),
                  SportPill(b['sport'], label: '${b['sport']['name']} · ${b['court']['name']}'),
                ]),
              ),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(color: C.ground, border: Border(top: BorderSide(color: C.dashed))),
          child: Row(children: [
            Expanded(child: KV('Date', b['date_label'], vSize: 13)),
            Expanded(child: KV('Time', b['time_short'], vSize: 13)),
            Expanded(child: KV(status == 'cancelled' ? 'Refund' : 'Paid', inr(status == 'cancelled' ? b['refund_amount'] : b['total']), vSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(b['note'] ?? '', style: t(12, c: C.muted))),
            const SizedBox(width: 10),
            if (status == 'confirmed')
              SizedBox(
                height: 40,
                child: Material(
                  color: C.brand,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await push(context, TicketScreen(bookingId: b['id']));
                      _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(children: [
                        const Icon(LucideIcons.qrCode, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('View ticket', style: t(13, w: FontWeight.w600, c: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            if (status == 'completed') ...[
              if (b['can_review'] == true) ...[
                GhostButton('Rate', height: 40, radius: 12, fontSize: 13, onTap: () => _rate(b)),
                const SizedBox(width: 8),
              ],
              GhostButton('Book again', height: 40, radius: 12, fontSize: 13, bg: C.mint, fg: C.green700, border: Colors.transparent,
                  onTap: () => BookingScreen.openForVenueId(context, b['venue']['id'], sportId: b['sport']['id'])),
            ],
            if (status == 'cancelled')
              GestureDetector(
                onTap: () => push(context, const PolicyScreen()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Refund policy', style: t(13, w: FontWeight.w600, c: C.brand, deco: TextDecoration.underline)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
