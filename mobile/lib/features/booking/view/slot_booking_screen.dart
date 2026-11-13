import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import '../../auth/auth_guard.dart';
import '../cubit/slot_booking_cubit.dart';
import '../cubit/slot_booking_state.dart';

/// 2 · Venue & Slot Matrix: horizontal date strip and a slot grid tagged Available / Open lobby / Booked.
/// After picking a slot the player chooses a play mode: Join solo (open lobbies on that slot) or
/// Create a group (Squad Builder). Also reschedules an existing booking when [SlotBookingArgs.reschedule] is given.
class SlotBookingScreen extends StatelessWidget {
  final SlotBookingArgs args;
  const SlotBookingScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => SlotBookingCubit(args: args, venues: c.read<VenueRepository>(), bookings: c.read<BookingRepository>()),
    child: const _SlotBookingView(),
  );
}

class _SlotBookingView extends StatefulWidget {
  const _SlotBookingView();
  @override
  State<_SlotBookingView> createState() => _SlotBookingViewState();
}

class _SlotBookingViewState extends State<_SlotBookingView> {
  SlotBookingCubit get _cubit => context.read<SlotBookingCubit>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final error = await _cubit.load();
    if (error != null && mounted) toast(context, error);
  }

  Future<void> _reschedule() async {
    if (!await requireProfile(context)) return;
    _cubit.setBusy(true);
    try {
      await _cubit.reschedule();
      if (!mounted) return;
      toast(context, 'Booking rescheduled');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, e.toString());
      _load();
    } finally {
      _cubit.setBusy(false);
    }
  }

  /// Play mode: Create a group → Squad Builder.
  Future<void> _createGroup() async {
    if (!await requireProfile(context) || !mounted) return;
    await context.pushSquadBuilder(_cubit.squadArgs());
    _load();
  }

  /// Play mode: Join solo → open lobbies on this slot.
  Future<void> _joinSolo() async {
    await context.pushLobbies(_cubit.lobbiesArgs());
    _load();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<SlotBookingCubit, SlotBookingState>(builder: _build);

  Widget _build(BuildContext context, SlotBookingState st) {
    final venue = st.venue, sports = st.sports;
    final today = st.today, date = st.date, day = st.day, dur = st.dur, start = st.start;
    final loading = st.loading, busy = st.busy, isReschedule = st.isReschedule, sportIdx = st.sportIdx, courtIdx = st.courtIdx;
    if (sports.isEmpty || st.courts.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackSquare(),
                const Spacer(),
                Center(
                  child: Text(
                    '${venue['name']} has no bookable courts yet. Please try another venue.',
                    textAlign: TextAlign.center,
                    style: t(15, c: C.muted, h: 1.5),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      );
    }
    final c = st.check;
    final sport = st.sport, court = st.court, courts = st.courts;
    final top = MediaQuery.of(context).padding.top;
    final dateLabel = '${DateFormat('EEE').format(date)}, ${date.day} ${DateFormat('MMM').format(date)}';
    final hrs = '$dur ${dur == 1 ? 'hr' : 'hrs'}';
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
                child: Row(
                  children: [
                    const BackSquare(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isReschedule ? 'Reschedule slot' : 'Pick a slot', style: d(20)),
                          Text(
                            '${venue['name']} · ${venue['area']}',
                            style: t(13, c: C.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x260C2419), blurRadius: 12, offset: Offset(0, 4))],
                      ),
                      child: Img(venue['image'], width: 48, height: 48, radius: BorderRadius.circular(12)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 190),
                  children: [
                    if (sports.length > 1 && !isReschedule)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: Segmented(
                          bg: const Color(0xFFE6ECE3),
                          height: 44,
                          labels: [for (final s in sports) s['name'] as String],
                          index: sportIdx,
                          onChanged: (i) {
                            _cubit.selectSport(i);
                            _load();
                          },
                        ),
                      ),
                    Label(DateFormat('MMMM yyyy').format(date)),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: 14,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final dd = DateTime(today.year, today.month, today.day).add(Duration(days: i));
                          final on = i == day;
                          return Semantics(
                            selected: on,
                            button: true,
                            label: DateFormat('EEEE d MMMM').format(dd),
                            child: GestureDetector(
                              onTap: () {
                                _cubit.selectDay(i);
                                _load();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 60,
                                decoration: BoxDecoration(
                                  color: on ? C.brand : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: on ? C.brand : C.line),
                                  boxShadow: on ? shadowBrandSm : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      i == 0 ? 'Today' : DateFormat('EEE').format(dd),
                                      style: t(12, w: FontWeight.w500, c: (on ? Colors.white : C.ink).withValues(alpha: 0.85)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${dd.day}', style: d(20, c: on ? Colors.white : C.ink)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Label('Court'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          for (var i = 0; i < courts.length && i < 4; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: Choice(
                                selected: i == courtIdx,
                                height: 60,
                                onTap: () {
                                  _cubit.selectCourt(i);
                                  _load();
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      courts[i]['name'],
                                      style: t(14, w: FontWeight.w700, c: i == courtIdx ? Colors.white : C.ink),
                                    ),
                                    Text(
                                      courts[i]['meta'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t(11, c: (i == courtIdx ? Colors.white : C.ink).withValues(alpha: 0.85)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isReschedule) ...[
                      const Label('Duration'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            for (final n in [1, 2, 3, 4]) ...[
                              if (n > 1) const SizedBox(width: 8),
                              Expanded(
                                child: Choice(
                                  selected: n == dur,
                                  height: 44,
                                  radius: 12,
                                  onTap: () => _cubit.setDuration(n),
                                  child: Text(
                                    '$n ${n == 1 ? 'hr' : 'hrs'}',
                                    style: t(14, w: FontWeight.w600, c: n == dur ? Colors.white : C.ink),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: C.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 6,
                            margin: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                            decoration: BoxDecoration(color: const Color(0xFFC9D4CC), borderRadius: BorderRadius.circular(999)),
                          ),
                          Text(
                            'PICK A START TIME',
                            textAlign: TextAlign.center,
                            style: t(11, w: FontWeight.w600, c: C.muted, ls: 1.2),
                          ),
                          const SizedBox(height: 14),
                          if (loading) const SlotGridSkeleton() else ..._groups(st, c.valid),
                          Container(
                            margin: const EdgeInsets.only(top: 18),
                            padding: const EdgeInsets.only(top: 14),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: C.line)),
                            ),
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 8,
                              children: [
                                _legend(
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: C.radioOff, width: 1.5),
                                    ),
                                  ),
                                  'Available',
                                ),
                                _legend(
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  'Selected',
                                ),
                                _legend(
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: C.limeSoft,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: C.green700, width: 1.5),
                                    ),
                                  ),
                                  'Open lobby',
                                ),
                                _legend(
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE9ECE6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  'Booked',
                                ),
                                _legend(
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFFB45309), shape: BoxShape.circle),
                                  ),
                                  'Peak price',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: C.line)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!c.valid && !loading && (isReschedule || st.lobbiesAtStart == 0))
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
                      child: Text(c.error, style: t(13, c: C.warnInk, h: 1.4)),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.valid
                                  ? '$dateLabel · ${fmtTime(start!)} – ${fmtTime(start + dur)}'
                                  : '$dateLabel · ${start == null ? '' : '${fmtHour(start)} start'}',
                              style: t(14, w: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text('${court?['name'] ?? ''} · ${sport['name']} · $hrs', style: t(12, c: C.muted)),
                          ],
                        ),
                      ),
                      if (!isReschedule)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(c.valid ? inr(c.total) : '₹—', style: d(22)),
                            Text('turf for the squad', style: t(11, c: C.muted)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isReschedule)
                    PrimaryButton(
                      'Confirm new slot',
                      height: 56,
                      radius: 16,
                      shadow: false,
                      loading: busy,
                      trailing: c.valid ? const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18) : null,
                      onTap: c.valid && !loading ? _reschedule : null,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: GhostButton(
                            st.lobbiesAtStart > 0 ? 'Join solo · ${st.lobbiesAtStart}' : 'Join solo',
                            icon: LucideIcons.userPlus,
                            height: 56,
                            bg: st.lobbiesAtStart > 0 ? C.limeSoft : C.chip,
                            fg: st.lobbiesAtStart > 0 ? C.green900 : C.muted,
                            border: Colors.transparent,
                            onTap: st.lobbiesAtStart > 0 && !loading ? _joinSolo : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            'Create a group',
                            height: 56,
                            radius: 16,
                            fontSize: 15,
                            shadow: false,
                            trailing: c.valid ? const Icon(LucideIcons.users, color: Colors.white, size: 18) : null,
                            onTap: c.valid && !loading ? _createGroup : null,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Widget box, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      box,
      const SizedBox(width: 6),
      Text(label, style: t(12, c: C.muted)),
    ],
  );

  List<Widget> _groups(SlotBookingState st, bool valid) {
    final slots = st.slots;
    const defs = [('Morning', 0, 11), ('Afternoon', 12, 15), ('Evening', 16, 19), ('Night', 20, 23)];
    final out = <Widget>[];
    for (final g in defs) {
      final hs = slots.where((s) => (s['hour'] as int) >= g.$2 && (s['hour'] as int) <= g.$3).toList();
      if (hs.isEmpty) continue;
      final first = hs.first['hour'] as int, last = hs.last['hour'] as int;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: t(13, w: FontWeight.w600),
                  children: [
                    TextSpan(text: g.$1),
                    TextSpan(
                      text: ' · ${fmtHour(first)} – ${fmtHour(last + 1)}',
                      style: t(13, c: C.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.45,
                children: [for (final s in hs) _slotTile(st, s, valid)],
              ),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _slotTile(SlotBookingState st, Json s, bool valid) {
    final start = st.start, dur = st.dur;
    final h = s['hour'] as int;
    final past = s['status'] == 'past', booked = s['status'] == 'booked';
    final lobbies = past ? 0 : ((s['lobbies'] as int?) ?? 0);
    final picked = start != null && h >= start && h < start + dur;
    final sel = valid && picked;
    final lobbyPick = !valid && h == start && lobbies > 0 && !st.isReschedule;
    final clash = !valid && h == start && !lobbyPick;
    Color bg = Colors.white, fg = C.ink;
    Border border = Border.all(color: C.radioOff, width: 1.5);
    if (past) {
      bg = C.ground;
      fg = const Color(0xFF57625A);
      border = Border.all(color: const Color(0xFFC9D4CC));
    } else if (lobbyPick) {
      bg = C.green700;
      fg = Colors.white;
      border = Border.all(color: C.green700);
    } else if (booked && lobbies == 0) {
      bg = const Color(0xFFE9ECE6);
      fg = const Color(0xFF57625A);
      border = Border.all(color: const Color(0xFFE9ECE6));
    } else if (sel) {
      bg = C.brand;
      fg = Colors.white;
      border = Border.all(color: C.brand);
    } else if (clash) {
      fg = C.warnInk;
      border = Border.all(color: const Color(0xFFB45309), width: 2);
    } else if (lobbies > 0) {
      bg = C.limeSoft;
      fg = C.green900;
      border = Border.all(color: C.green700, width: 1.5);
    }
    final tappable = !past && (!booked || (lobbies > 0 && !st.isReschedule));
    final spots = (s['lobby_spots'] as int?) ?? 0;
    final peak = s['peak'] == true && !past && !booked && !sel && lobbies == 0;
    return Semantics(
      button: true,
      enabled: tappable,
      selected: sel || lobbyPick,
      label:
          '${s['label']}${past
              ? ', past'
              : lobbies > 0
              ? ', open lobby, $spots spots left'
              : booked
              ? ', booked'
              : ', ${inr(s['price'])}${s['peak'] == true ? ', peak price' : ''}'}',
      child: GestureDetector(
        onTap: tappable ? () => _cubit.pickStart(h) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border,
            boxShadow: sel || lobbyPick ? const [BoxShadow(color: Color(0x47143D2B), blurRadius: 14, offset: Offset(0, 6))] : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s['label'],
                      style: t(13, w: FontWeight.w700, c: fg, deco: booked && lobbies == 0 ? TextDecoration.lineThrough : null),
                    ),
                    Text(
                      past
                          ? 'Past'
                          : lobbies > 0
                          ? '$spots left'
                          : booked
                          ? 'Booked'
                          : inr(s['price']),
                      style: t(10, w: FontWeight.w500, c: fg.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              if (peak)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Color(0xFFB45309), shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
