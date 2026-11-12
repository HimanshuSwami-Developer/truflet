import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/play_repository.dart';
import '../../../data/repositories/squad_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import '../../booking/open_slot_booking.dart';
import '../cubit/create_cubit.dart';
import '../cubit/create_state.dart';

/// 15 · Create match / tournament (4 steps)
class CreateScreen extends StatelessWidget {
  final String type; // 'match' | 'tour'
  const CreateScreen({super.key, this.type = 'tour'});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) =>
        CreateCubit(
            type: type,
            play: c.read<PlayRepository>(),
            venues: c.read<VenueRepository>(),
            squad: c.read<SquadRepository>(),
            app: c.read<AppCubit>(),
          )
          ..init()
          ..loadGroups(),
    child: _CreateView(type: type),
  );
}

class _CreateView extends StatefulWidget {
  final String type;
  const _CreateView({required this.type});
  @override
  State<_CreateView> createState() => _CreateViewState();
}

class _CreateViewState extends State<_CreateView> {
  late final name = TextEditingController(text: CreateCubit.defaultName(widget.type));

  CreateCubit get _cubit => context.read<CreateCubit>();

  // Read-only view of the draft, so the layout code below reads like plain fields.
  CreateState get _st => _cubit.state;
  String get type => _st.type;
  int get step => _st.step;
  bool get nameErr => _st.nameErr;
  List<Json> get sports => _st.sports;
  int get sportIdx => _st.sportIdx;
  Json get sport => _st.sport;
  String get format => _st.format;
  int get teams => _st.teams;
  int get perTeam => _st.perTeam;
  int get fee => _st.fee;
  int get groupIdx => _st.groupIdx;
  int get venueIdx => _st.venueIdx;
  int get dateIdx => _st.dateIdx;
  int get timeIdx => _st.timeIdx;
  bool get balance => _st.balance;
  bool get busy => _st.busy;
  bool get isTour => _st.isTour;
  List<Json> get venues => _st.venues;
  List<Json> get groups => _st.groups;
  Json? get venue => _st.venue;
  Json? get done => _st.done;
  String? get loadError => _st.loadError;
  List<DateTime> get dates => _st.dates;
  ({int matches, int days, int perDay, int courts, int courtHours, int venueCost, int collected}) get plan => _st.plan;

  void _setType(String t) {
    name.text = CreateCubit.defaultName(t);
    _cubit.setType(t);
  }

  void _next() {
    final message = _cubit.next(name.text);
    if (message != null) toast(context, message);
  }

  Future<void> _publish() async {
    final error = await _cubit.publish(name.text);
    if (error != null && mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<CreateCubit, CreateState>(builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    if (done != null) return _done();
    if (sports.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: SquareIconButton(LucideIcons.x, label: 'Close'),
                ),
              ),
              Expanded(
                child: loadError != null
                    ? ErrorRetry(loadError!, onRetry: _cubit.init)
                    : const Align(alignment: Alignment.topCenter, child: FormSkeleton()),
              ),
            ],
          ),
        ),
      );
    }
    final top = MediaQuery.of(context).padding.top;
    final steps = ['Basics', isTour ? 'Teams' : 'Players', 'Venue & time', 'Review'];
    final heads = isTour
        ? ['Host a tournament', 'Teams & entry', 'Where & when', 'Review & publish']
        : ['Set up a match', 'Who is playing?', 'Where & when', 'Review & invite'];
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cubit.back();
      },
      child: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, top + 8, 20, 0),
              child: Row(
                children: [
                  step == 0
                      ? const SquareIconButton(LucideIcons.x, label: 'Close')
                      : SquareIconButton(LucideIcons.chevronLeft, label: 'Previous step', onTap: _cubit.back),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Step ${step + 1} of 4 · ${steps[step]}', style: t(12, c: C.muted)),
                        Text(heads[step], style: d(20)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= step ? C.brand : const Color(0xFFD9E2D5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  if (step == 0) ..._basics(),
                  if (step == 1) ...(isTour ? _teams() : _players()),
                  if (step == 2) ..._where(),
                  if (step == 3) ..._review(),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: C.line)),
              ),
              child: PrimaryButton(
                step < 3
                    ? 'Continue'
                    : isTour
                    ? 'Publish tournament'
                    : 'Create match & send invites',
                loading: busy,
                onTap: step < 3 ? _next : _publish,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lbl(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: t(13, w: FontWeight.w600)),
  );

  Widget _rowBtn({required bool on, required VoidCallback onTap, required Widget child}) => Semantics(
    checked: on,
    inMutuallyExclusiveGroup: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? C.brand : C.line, width: 2),
        ),
        child: child,
      ),
    ),
  );

  Widget _pill(String label, bool on, VoidCallback onTap) => Choice(
    selected: on,
    onTap: onTap,
    child: Text(
      label,
      style: t(14, w: FontWeight.w700, c: on ? Colors.white : C.ink),
    ),
  );

  Widget _stepper(String title, String sub) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: C.line),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t(13, w: FontWeight.w600)),
              Text(sub, style: t(12, c: C.muted)),
            ],
          ),
        ),
        _sq('−', false, _cubit.fewerPlayers, 'Fewer players'),
        SizedBox(
          width: 48,
          child: Text('$perTeam', textAlign: TextAlign.center, style: d(20)),
        ),
        _sq('+', true, _cubit.morePlayers, 'More players'),
      ],
    ),
  );

  Widget _sq(String s, bool primary, VoidCallback onTap, String label) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? C.brand : C.ground,
          borderRadius: BorderRadius.circular(12),
          border: primary ? null : Border.all(color: C.line),
        ),
        child: Text(
          s,
          style: t(20, w: FontWeight.w700, c: primary ? Colors.white : C.ink),
        ),
      ),
    ),
  );

  List<Widget> _basics() => [
    Row(
      children: [
        for (final tt in [
          ('match', 'Quick match', 'One game with your group', LucideIcons.volleyball),
          ('tour', 'Tournament', 'Many teams, auto fixtures', LucideIcons.trophy),
        ]) ...[
          if (tt.$1 == 'tour') const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _setType(tt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 116),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: type == tt.$1 ? C.mint : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: type == tt.$1 ? C.brand : C.line, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tt.$4, size: 26, color: type == tt.$1 ? C.green900 : C.ink),
                    const SizedBox(height: 6),
                    Text(
                      tt.$2,
                      style: t(15, w: FontWeight.w700, c: type == tt.$1 ? C.green900 : C.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(tt.$3, style: t(12, c: (type == tt.$1 ? C.green900 : C.ink).withValues(alpha: 0.85), h: 1.35)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
    const SizedBox(height: 18),
    _lbl(isTour ? 'Tournament name' : 'Match name'),
    Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: nameErr ? C.redInk : C.line),
      ),
      child: TextField(
        controller: name,
        onChanged: (_) => _cubit.clearNameError(),
        style: t(15),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: isTour ? 'e.g. HSR Night Cup' : 'e.g. Sunday friendly',
          hintStyle: t(15, c: C.muted),
        ),
      ),
    ),
    if (nameErr)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Please add a name to continue.', style: t(12, c: C.redInk)),
      ),
    const SizedBox(height: 18),
    _lbl('Sport'),
    GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        for (var i = 0; i < sports.length; i++)
          GestureDetector(
            onTap: () => _cubit.selectSport(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              decoration: BoxDecoration(
                color: i == sportIdx ? hex(sports[i]['bg']) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: i == sportIdx ? hex(sports[i]['fg']) : C.line, width: 2),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Img(sports[i]['image'], width: double.infinity, radius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sports[i]['name'],
                    style: t(12, w: FontWeight.w700, c: i == sportIdx ? hex(sports[i]['fg']) : C.ink),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
    if (isTour) ...[
      const SizedBox(height: 18),
      _lbl('Format'),
      for (final f in createFormats)
        _rowBtn(
          on: format == f.$1,
          onTap: () => _cubit.setFormat(f.$1),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.$2, style: t(14, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(f.$3, style: t(12, c: C.muted)),
                  ],
                ),
              ),
              RadioDot(format == f.$1),
            ],
          ),
        ),
    ],
  ];

  List<Widget> _teams() => [
    _lbl('Number of teams'),
    Row(
      children: [
        for (final n in [4, 8, 16]) ...[
          if (n != 4) const SizedBox(width: 8),
          Expanded(child: _pill('$n teams', n == teams, () => _cubit.setTeams(n))),
        ],
      ],
    ),
    const SizedBox(height: 18),
    _stepper('Players per team', 'Including substitutes'),
    const SizedBox(height: 18),
    _lbl('Entry fee per team'),
    Row(
      children: [
        for (final n in [0, 1000, 2000, 3000]) ...[
          if (n != 0) const SizedBox(width: 8),
          Expanded(child: _pill(n == 0 ? 'Free' : inr(n), n == fee, () => _cubit.setFee(n))),
        ],
      ],
    ),
    const SizedBox(height: 18),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 18, color: C.blueInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Captains register through a shared link and pay entry online. You can also add teams from your groups.',
              style: t(13, c: C.blueInk, h: 1.5),
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _players() => [
    _lbl('Invite from'),
    for (var i = 0; i <= groups.length; i++)
      _rowBtn(
        on: i == groupIdx,
        onTap: () => _cubit.selectGroup(i),
        child: Row(
          children: [
            i < groups.length
                ? Img(groups[i]['image'], width: 44, height: 44, radius: BorderRadius.circular(12))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/images/turf.jpg', width: 44, height: 44, fit: BoxFit.cover),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i < groups.length ? groups[i]['name'] : 'Invite friends individually', style: t(14, w: FontWeight.w700)),
                  Text(
                    i < groups.length
                        ? '${groups[i]['member_count']} members · ${groups[i]['sport']['name']}'
                        : 'Share the match link',
                    style: t(12, c: C.muted),
                  ),
                ],
              ),
            ),
            RadioDot(i == groupIdx),
          ],
        ),
      ),
    const SizedBox(height: 10),
    _stepper('Players per side', '${perTeam * 2} players total'),
    const SizedBox(height: 18),
    Semantics(
      toggled: balance,
      child: GestureDetector(
        onTap: _cubit.toggleBalance,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-balance teams', style: t(13, w: FontWeight.w600)),
                    Text('Splits players fairly by skill level once RSVPs close', style: t(12, c: C.muted)),
                  ],
                ),
              ),
              Toggle(balance),
            ],
          ),
        ),
      ),
    ),
  ];

  List<Widget> _where() {
    final p = plan;
    final win = createWindows[timeIdx];
    return [
      _lbl('Venue'),
      if (venues.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('No venues offer ${sport['name']} in your city yet.', style: t(13, c: C.muted)),
        ),
      for (var i = 0; i < venues.length && i < 6; i++)
        _rowBtn(
          on: i == venueIdx,
          onTap: () => _cubit.selectVenue(i),
          child: Row(
            children: [
              Img(venues[i]['image'], width: 56, height: 56, radius: BorderRadius.circular(14)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venues[i]['name'], style: t(14, w: FontWeight.w700)),
                    Text('${venues[i]['area']} · ${inr(venues[i]['price_from'])}/hr', style: t(12, c: C.muted)),
                  ],
                ),
              ),
              RadioDot(i == venueIdx),
            ],
          ),
        ),
      const SizedBox(height: 10),
      _lbl(isTour ? 'Start date' : 'Date'),
      Row(
        children: [
          for (var i = 0; i < dates.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Choice(
                selected: i == dateIdx,
                height: 60,
                onTap: () => _cubit.selectDate(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(dates[i]),
                      style: t(11, c: (i == dateIdx ? Colors.white : C.ink).withValues(alpha: 0.85)),
                    ),
                    Text('${dates[i].day}', style: d(18, c: i == dateIdx ? Colors.white : C.ink)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      _lbl(isTour ? 'Daily playing window' : 'Start time'),
      Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _pill(isTour ? createWindows[i].$2 : fmtHour(createMatchTimes[i]), i == timeIdx, () => _cubit.selectTime(i)),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.limeSoft, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTour
                  ? '${p.matches} matches · ${p.days} ${p.days == 1 ? 'day' : 'days'} on ${p.courts} courts'
                  : '${fmtHour(createMatchTimes[timeIdx])} · 1 hr · ${venue?['name'] ?? ''}',
              style: t(13, w: FontWeight.w700, c: const Color(0xFF1F4D0F)),
            ),
            const SizedBox(height: 4),
            Text(
              isTour
                  ? 'Each ${sport['name'].toString().toLowerCase()} match ≈ ${sport['match_minutes']} min. Up to ${p.perDay} matches fit per day in the ${win.$3} window. Fixtures are generated automatically.'
                  : 'Slot is held for 10 minutes after you send invites. Cost is split between players who say In.',
              style: t(12, c: const Color(0xFF2F5E1A), h: 1.5),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _review() {
    final p = plan;
    final d0 = dates[dateIdx];
    final when =
        '${DateFormat('EEE').format(d0)}, ${d0.day} ${DateFormat('MMM').format(d0)} · ${isTour ? createWindows[timeIdx].$3 : fmtHour(createMatchTimes[timeIdx])}';
    final shown = name.text.trim().isEmpty ? (isTour ? 'My tournament' : 'Friendly match') : name.text.trim();
    final rows = isTour
        ? [
            ('Format', createFormats.firstWhere((f) => f.$1 == format).$2),
            ('Teams', '$teams teams × $perTeam players'),
            ('Fixtures', '${p.matches} matches over ${p.days} ${p.days == 1 ? 'day' : 'days'}'),
            ('Venue', venue?['name'] ?? ''),
            ('Starts', when),
          ]
        : [
            ('Players', '$perTeam vs $perTeam${balance ? ' · auto-balanced' : ''}'),
            ('Invites to', groupIdx < groups.length ? groups[groupIdx]['name'] : 'Friends (link)'),
            ('Venue', venue?['name'] ?? ''),
            ('When', when),
          ];
    final left = p.collected - p.venueCost;
    final price = (venue?['price_from'] ?? 0) as int;
    final money = isTour
        ? [
            ('Entry collected ($teams × ${inr(fee)})', inr(p.collected)),
            ('Venue cost (${p.courtHours} court-hrs)', '−${inr(p.venueCost)}'),
            (left >= 0 ? 'Left for prizes' : 'You cover', inr(left.abs())),
          ]
        : [
            ('Slot cost (1 hr)', inr(price)),
            ('Players', '${perTeam * 2}'),
            ('Each player pays', inr((price / (perTeam * 2)).ceil())),
          ];
    return [
      Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: shadowCard),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Img(sport['image']),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.2, 1],
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${isTour ? 'TOURNAMENT' : 'QUICK MATCH'} · ${sport['name'].toString().toUpperCase()}',
                          style: t(11, w: FontWeight.w700, c: Colors.white, ls: 0.5),
                        ),
                        Text(shown, style: d(20, c: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: i < rows.length - 1
                          ? const BoxDecoration(
                              border: Border(bottom: BorderSide(color: C.divider)),
                            )
                          : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].$1, style: t(14, c: C.muted)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              rows[i].$2,
                              textAlign: TextAlign.right,
                              style: t(14, w: FontWeight.w600),
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
      ),
      const SizedBox(height: 14),
      CardBox(
        padding: const EdgeInsets.all(14),
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Money', size: 16),
            const SizedBox(height: 8),
            for (var i = 0; i < money.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: i == money.length - 1
                    ? PriceRow(money[i].$1, money[i].$2, bold: true, top: true, color: isTour && left < 0 ? C.orange : C.green700)
                    : PriceRow(money[i].$1, money[i].$2),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _done() {
    final link = (done!['link'] ?? '').toString();
    final groupName = done!['invited_to'] ?? '';
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: C.brand,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x2616803C), spreadRadius: 10)],
              ),
              child: const Icon(LucideIcons.check, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(isTour ? 'Tournament published!' : 'Match created!', style: d(26)),
            const SizedBox(height: 16),
            Text(
              isTour
                  ? 'Share the registration link with team captains. Fixtures go live as soon as all $teams teams register.'
                  : "Invites sent to $groupName. Book the slot now so it isn't taken.",
              textAlign: TextAlign.center,
              style: t(14, c: C.muted, h: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: C.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      link,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(13, c: C.blueInk),
                    ),
                  ),
                  GhostButton(
                    'Share',
                    height: 38,
                    radius: 10,
                    bg: C.blue,
                    fg: Colors.white,
                    border: Colors.transparent,
                    fontSize: 13,
                    onTap: () =>
                        SharePlus.instance.share(ShareParams(text: 'Join ${name.text.trim()} on Turflet: https://$link')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              isTour ? 'Open host dashboard' : 'Book & pay for the slot',
              shadow: false,
              onTap: () {
                if (isTour) {
                  context.replaceWithTournament(done!['id']);
                } else {
                  openSlotBooking(
                    context,
                    done!['venue_id'],
                    sportId: done!['sport_id'],
                    date: DateTime.parse(done!['date']),
                    startHour: done!['start_hour'],
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Back to Play',
                style: t(14, w: FontWeight.w600, c: C.brand),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
