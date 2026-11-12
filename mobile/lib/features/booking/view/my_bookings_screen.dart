import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../app/session/app_state.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import '../cubit/my_bookings_cubit.dart';
import '../open_slot_booking.dart';

/// 9 · My bookings
class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => MyBookingsCubit(bookings: c.read<BookingRepository>(), venues: c.read<VenueRepository>())..load(),
    // refresh whenever the player switches to this tab
    child: BlocListener<AppCubit, AppState>(
      listenWhen: (prev, cur) => cur.tab == AppTab.bookings && prev.tab != AppTab.bookings,
      listener: (context, _) => context.read<MyBookingsCubit>().load(),
      child: const _MyBookingsView(),
    ),
  );
}

class _MyBookingsView extends StatelessWidget {
  const _MyBookingsView();

  Future<void> _rate(BuildContext context, Json b) async {
    var stars = 5;
    final ok = await sheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Rate ${b['venue']['name']}', style: d(20)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      iconSize: 40,
                      onPressed: () => set(() => stars = i),
                      icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: C.star),
                      tooltip: '$i stars',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton('Submit', height: 52, onTap: () => Navigator.pop(ctx, true)),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      await context.read<MyBookingsCubit>().rate(b, stars);
      if (context.mounted) toast(context, 'Thanks for rating!');
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<MyBookingsCubit, MyBookingsState>(builder: _build);

  Widget _build(BuildContext context, MyBookingsState st) {
    final cubit = context.read<MyBookingsCubit>();
    final app = context.watch<AppCubit>();
    final s = app.state;
    final data = st.data, error = st.error, tab = st.tab;
    final top = MediaQuery.of(context).padding.top;
    final counts = asMap(data?['counts']);
    return RefreshIndicator(
      color: C.brand,
      onRefresh: cubit.load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, top + 12, 0, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My bookings', style: d(28, ls: -0.5)),
                      const SizedBox(height: 4),
                      Text('Linked to ${s.user?['masked_email'] ?? ''}', style: t(13, c: C.muted)),
                    ],
                  ),
                ),
                GhostButton(
                  'Help',
                  icon: LucideIcons.circleHelp,
                  height: 40,
                  radius: 999,
                  fontSize: 13,
                  onTap: () => context.pushHelp(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Segmented(
              labels: const ['Upcoming', 'Completed', 'Cancelled'],
              counts: [counts['upcoming'] ?? 0, counts['completed'] ?? 0, counts['cancelled'] ?? 0],
              index: tab,
              onChanged: cubit.selectTab,
            ),
          ),
          const SizedBox(height: 16),
          if (error != null) ErrorRetry(error, onRetry: cubit.load),
          if (data == null && error == null) const BookingCardsSkeleton(),
          if (data != null && asList(data['items']).isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Icon(LucideIcons.calendar, size: 40, color: C.muted),
                  const SizedBox(height: 12),
                  Text(
                    ['No upcoming games. Book a slot!', 'No completed games yet.', 'No cancellations.'][tab],
                    style: t(14, c: C.muted),
                    textAlign: TextAlign.center,
                  ),
                  if (tab == 0) ...[
                    const SizedBox(height: 16),
                    PrimaryButton('Explore turfs', height: 48, onTap: () => app.setTab(AppTab.explore)),
                  ],
                ],
              ),
            ),
          for (final b in asList(data?['items']))
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 14), child: _card(context, b)),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Json b) {
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
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              await context.pushTicket(b['id']);
              if (context.mounted) context.read<MyBookingsCubit>().load();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Img(b['venue']['image'], width: 76, height: 76, radius: BorderRadius.circular(16)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(b['venue']['name'], style: d(16, h: 1.2))),
                            const SizedBox(width: 8),
                            Pill(
                              statusStyle.$1,
                              bg: statusStyle.$2,
                              fg: statusStyle.$3,
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(km, style: t(13, c: C.muted)),
                        const SizedBox(height: 4),
                        SportPill(b['sport'], label: '${b['sport']['name']} · ${b['court']['name']}'),
                        if (b['open_game'] != null || b['group'] != null) ...[
                          const SizedBox(height: 6),
                          b['group'] != null
                              ? Pill('With ${b['group']['name']}', bg: C.blueSoft, fg: C.blue)
                              : Pill(
                                  '${b['role'] == 'player' ? 'Joined open game' : 'Open game'} · '
                                  '${b['open_game']['joined_count']}/${b['open_game']['total_players']} in',
                                  bg: C.limeSoft,
                                  fg: C.green700,
                                ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: C.ground,
              border: Border(top: BorderSide(color: C.dashed)),
            ),
            child: Row(
              children: [
                Expanded(child: KV('Date', b['date_label'], vSize: 13)),
                Expanded(child: KV('Time', b['time_short'], vSize: 13)),
                Expanded(
                  child: KV(
                    status == 'cancelled' ? 'Refund' : 'Paid',
                    inr(status == 'cancelled' ? b['refund_amount'] : (b['my_paid'] ?? b['total'])),
                    vSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(b['note'] ?? '', style: t(12, c: C.muted)),
                ),
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
                          await context.pushTicket(b['id']);
                          if (context.mounted) context.read<MyBookingsCubit>().load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.qrCode, size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                'View ticket',
                                style: t(13, w: FontWeight.w600, c: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (status == 'completed') ...[
                  if (b['can_review'] == true) ...[
                    GhostButton('Rate', height: 40, radius: 12, fontSize: 13, onTap: () => _rate(context, b)),
                    const SizedBox(width: 8),
                  ],
                  GhostButton(
                    'Book again',
                    height: 40,
                    radius: 12,
                    fontSize: 13,
                    bg: C.mint,
                    fg: C.green700,
                    border: Colors.transparent,
                    onTap: () => openSlotBooking(context, b['venue']['id'], sportId: b['sport']['id']),
                  ),
                ],
                if (status == 'cancelled')
                  GestureDetector(
                    onTap: () => context.pushPolicy(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Refund policy',
                        style: t(13, w: FontWeight.w600, c: C.brand, deco: TextDecoration.underline),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
