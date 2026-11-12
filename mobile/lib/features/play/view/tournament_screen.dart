import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/play_repository.dart';
import '../cubit/tournament_cubit.dart';

/// 16 · Tournament host dashboard (fixtures, live scoring, teams & payments).
/// Players who are not the host see the same page read-only.
class TournamentScreen extends StatelessWidget {
  final int id;
  const TournamentScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => TournamentCubit(id: id, repository: c.read<PlayRepository>())..load(),
    child: const _TournamentView(),
  );
}

class _TournamentView extends StatefulWidget {
  const _TournamentView();
  @override
  State<_TournamentView> createState() => _TournamentViewState();
}

class _TournamentViewState extends State<_TournamentView> with SingleTickerProviderStateMixin {
  TournamentCubit get _cubit => context.read<TournamentCubit>();
  late final blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    blink.dispose();
    super.dispose();
  }

  /// Runs a cubit action and toasts the outcome.
  Future<void> _act(Future<String?> Function() action, [String? ok]) async {
    final error = await action();
    if (!mounted) return;
    if (error != null) {
      toast(context, error);
    } else if (ok != null) {
      toast(context, ok);
    }
  }

  Future<void> _addTeam() async {
    final ctl = TextEditingController();
    final capt = TextEditingController();
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a team', style: d(22)),
          const SizedBox(height: 14),
          _input(ctl, 'Team name', 'e.g. Night Owls'),
          const SizedBox(height: 10),
          _input(capt, 'Captain (optional)', 'e.g. Faiz A.'),
          const SizedBox(height: 16),
          PrimaryButton('Add team', height: 52, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await _act(() => _cubit.addTeam(ctl.text.trim(), capt.text.trim()));
    }
  }

  Widget _input(TextEditingController c, String label, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: t(13, w: FontWeight.w600)),
      const SizedBox(height: 6),
      Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: C.ground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: TextField(
          controller: c,
          style: t(15),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hint,
            hintStyle: t(15, c: C.muted),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => BlocBuilder<TournamentCubit, TournamentState>(builder: _build);

  Widget _build(BuildContext context, TournamentState st) {
    final data = st.data, error = st.error, tab = st.tab, busy = st.busy;
    if (data == null) {
      return Scaffold(body: error != null ? ErrorRetry(error, onRetry: _cubit.load) : const HeroPageSkeleton());
    }
    final tt = data;
    final top = MediaQuery.of(context).padding.top;
    final host = tt['is_host'] == true;
    final status = tt['status'];
    final myTeam = asList(tt['teams']).where((x) => x['is_mine'] == true).firstOrNull;
    return Scaffold(
      body: RefreshIndicator(
        color: C.brand,
        onRefresh: _cubit.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            SizedBox(
              height: 200,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Img(tt['image'], fallback: 'stumps'),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.4, 1],
                        colors: [Color(0x66000000), Color(0x26000000), Color(0xBF000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: top + 8,
                    left: 20,
                    right: 20,
                    child: Row(
                      children: [
                        const BackSquare(translucent: true),
                        const Spacer(),
                        Material(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => SharePlus.instance.share(
                              ShareParams(text: '${tt['name']} on Turflet — follow live: https://${tt['link']}'),
                            ),
                            child: SizedBox(
                              height: 44,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.share2, size: 16, color: C.blue),
                                    const SizedBox(width: 6),
                                    Text(
                                      status == 'live' ? 'Share live' : 'Share',
                                      style: t(13, w: FontWeight.w700, c: C.blue),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Pill(
                              tt['day_label'] ?? '',
                              bg: status == 'live' ? C.red : Colors.white,
                              fg: status == 'live' ? Colors.white : C.ink,
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            ),
                            if (host) ...[
                              const SizedBox(width: 6),
                              const Pill(
                                "You're the host",
                                bg: C.lime,
                                fg: C.ink,
                                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(tt['name'], style: d(24, c: Colors.white)),
                        Text(
                          '${tt['sport']['name']} · ${tt['format_label']} · ${tt['team_count']} teams · ${tt['venue']}',
                          style: t(13, c: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                  Expanded(child: Stat('Matches', '${tt['played']}/${tt['total_matches']}')),
                  const SizedBox(width: 8),
                  Expanded(child: Stat('Collected', inr(tt['collected']))),
                  const SizedBox(width: 8),
                  Expanded(child: Stat('Prize pool', inr(tt['prize_pool']), color: C.green700)),
                ],
              ),
            ),
            if (!host && status == 'open')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: myTeam == null
                    ? PrimaryButton(
                        'Register a team · ${tt['fee_label']}',
                        height: 52,
                        onTap: () => _act(_cubit.registerTeam, 'Team registered'),
                      )
                    : myTeam['paid'] == true
                    ? Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
                        child: Text(
                          '${myTeam['name']} is registered and paid. See you on match day!',
                          style: t(13, w: FontWeight.w600, c: C.green900),
                        ),
                      )
                    : PrimaryButton(
                        'Pay entry ${inr(tt['entry_fee'])} for ${myTeam['name']}',
                        height: 52,
                        loading: busy,
                        onTap: () => _act(() => _cubit.payEntry(myTeam['id']), 'Entry paid'),
                      ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Segmented(labels: const ['Fixtures', 'Teams & payments'], index: tab, onChanged: _cubit.selectTab),
            ),
            if (tab == 0) ..._fixtures(tt, host, busy) else ..._teams(tt, host),
          ],
        ),
      ),
    );
  }

  List<Widget> _fixtures(Json tt, bool host, bool busy) {
    final rounds = asList(tt['rounds']);
    if (rounds.isEmpty) {
      final teams = asList(tt['teams']).length;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Fixtures are not out yet', style: d(16)),
                const SizedBox(height: 6),
                Text(
                  '$teams of ${tt['team_count']} teams registered. Fixtures are generated automatically once you start.',
                  style: t(13, c: C.muted, h: 1.5),
                ),
                if (host) ...[
                  const SizedBox(height: 14),
                  PrimaryButton(
                    'Generate fixtures',
                    height: 50,
                    loading: busy,
                    shadow: false,
                    onTap: teams < 2 ? null : () => _act(_cubit.generateFixtures, 'Fixtures ready'),
                  ),
                  const SizedBox(height: 8),
                  GhostButton('Add a team manually', icon: LucideIcons.plus, height: 46, onTap: _addTeam),
                ],
              ],
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in rounds) ...[
              Text(
                r['name'].toString().toUpperCase(),
                style: t(13, w: FontWeight.w600, c: C.muted, ls: 0.6),
              ),
              const SizedBox(height: 8),
              if (r['cols'] == 2)
                // two cards per row; each row is as tall as its tallest card (no fixed aspect ratio)
                for (final pair in _pairs(asList(r['matches'])))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _match(pair[0], host, compact: true)),
                          const SizedBox(width: 8),
                          Expanded(child: pair.length > 1 ? _match(pair[1], host, compact: true) : const SizedBox()),
                        ],
                      ),
                    ),
                  )
              else
                for (final m in asList(r['matches'])) Padding(padding: const EdgeInsets.only(bottom: 8), child: _match(m, host)),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    ];
  }

  List<List<Json>> _pairs(List<Json> items) => [
    for (var i = 0; i < items.length; i += 2) items.sublist(i, (i + 2).clamp(0, items.length)),
  ];

  Widget _match(Json m, bool host, {bool compact = false}) {
    final live = m['state'] == 'live', done = m['state'] == 'done';
    final tag = {
      'FT': (C.chip, C.muted),
      'LIVE': (C.redSoft, C.redInk),
      'NEXT': (C.blueSoft, const Color(0xFF1E40AF)),
      'FINAL': (C.amberSoft, C.amber),
      'TBD': (C.amberSoft, C.amber),
    }[m['tag']]!;
    TextStyle side(String s) =>
        done && m['winner'] == s ? t(14, w: FontWeight.w700) : t(14, w: FontWeight.w500, c: done ? C.muted : C.ink);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: live ? const Color(0xFFFCA5A5) : C.line, width: live ? 2 : 1),
        boxShadow: live ? const [BoxShadow(color: Color(0x1FDC2626), blurRadius: 18, offset: Offset(0, 6))] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Pill(m['tag'], bg: tag.$1, fg: tag.$2, size: 10, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
              const Spacer(),
              Flexible(
                child: Text(
                  m['meta'] ?? '',
                  style: t(11, c: C.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(m['a'], style: side('a'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(m['a_score'] ?? '', style: side('a')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(m['b'], style: side('b'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(m['b_score'] ?? '', style: side('b')),
            ],
          ),
          if (!compact && done && (m['result'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              m['result'],
              style: t(12, c: C.green700, w: FontWeight.w600),
            ),
          ],
          if (live && host) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: Material(
                color: C.red,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _score(m),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: blink,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Update live score',
                        style: t(14, w: FontWeight.w700, c: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (m['can_start'] == true && host && !compact) ...[
            const SizedBox(height: 10),
            GhostButton(
              'Start match',
              height: 40,
              radius: 12,
              fg: C.brand,
              border: C.brand,
              fontSize: 13,
              onTap: () => _act(() => _cubit.startFixture(m['id']), 'Match is live'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _score(Json m) async {
    var f = m;
    var working = false;
    await sheet(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Future<void> call(String action, [Json body = const {}]) async {
            if (working) return;
            set(() => working = true);
            try {
              final r = await _cubit.score(f['id'], action, body);
              if (action == 'confirm') {
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              set(() => f = r);
            } catch (e) {
              if (mounted) toast(context, e.toString());
            } finally {
              set(() => working = false);
            }
          }

          final lv = asMap(f['live']);
          final cricket = lv['scoring'] == 'cricket';
          final result = lv['result'];
          final round = f['label'] == 'F'
              ? 'Final'
              : '${f['round'].toString().replaceAll(RegExp(r's$'), '')} ${f['label'].toString().replaceAll(RegExp(r'\D'), '')}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('$round · Scoring', style: d(20))),
                  SquareIconButton(
                    LucideIcons.x,
                    size: 40,
                    iconSize: 18,
                    label: 'Close scoring',
                    onTap: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(18)),
                child: cricket
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: t(14, w: FontWeight.w700),
                                    children: [
                                      TextSpan(text: '${lv['batting']} '),
                                      TextSpan(
                                        text: 'batting',
                                        style: t(14, w: FontWeight.w500, c: C.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  style: d(28),
                                  children: [
                                    TextSpan(text: '${lv['runs']}/${lv['wkts']} '),
                                    TextSpan(
                                      text: '(${lv['overs']})',
                                      style: d(15, c: C.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(lv['other_line'] ?? '', style: t(13, c: C.muted)),
                              ),
                              if (lv['target'] != null) Text('Target ${lv['target']}', style: t(13, c: C.muted)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lv['equation'] ?? '',
                            style: t(13, w: FontWeight.w700, c: result != null ? C.green700 : C.redInk),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(lv['a'], style: t(14, w: FontWeight.w700)),
                                Text('${lv['a_points']}', style: d(32)),
                              ],
                            ),
                          ),
                          Text('–', style: d(28, c: C.muted)),
                          Expanded(
                            child: Column(
                              children: [
                                Text(lv['b'], style: t(14, w: FontWeight.w700)),
                                Text('${lv['b_points']}', style: d(32)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              if (cricket && result == null) ...[
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                  children: [
                    for (final b in const [
                      ('0', 0, 0, 1, 'Dot ball'),
                      ('1', 1, 0, 1, 'One run'),
                      ('2', 2, 0, 1, 'Two runs'),
                      ('3', 3, 0, 1, 'Three runs'),
                      ('4', 4, 0, 1, 'Four'),
                      ('6', 6, 0, 1, 'Six'),
                      ('WD', 1, 0, 0, 'Wide, one run'),
                      ('OUT', 0, 1, 1, 'Wicket'),
                    ])
                      _ballBtn(b.$1, b.$5, () => call('ball', {'runs': b.$2, 'wicket': b.$3, 'legal': b.$4})),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        'Undo last ball',
                        height: 44,
                        radius: 12,
                        onTap: lv['can_undo'] == true ? () => call('undo') : null,
                      ),
                    ),
                    if (lv['innings'] == 1) ...[
                      const SizedBox(width: 8),
                      Expanded(child: GhostButton('End innings', height: 44, radius: 12, onTap: () => call('end-innings'))),
                    ],
                  ],
                ),
              ],
              if (!cricket && result == null) ...[
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        '+1 ${lv['a']}',
                        height: 52,
                        shadow: false,
                        fontSize: 14,
                        onTap: () => call('ball', {'side': 'a', 'runs': 1}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryButton(
                        '+1 ${lv['b']}',
                        height: 52,
                        shadow: false,
                        fontSize: 14,
                        color: C.blue,
                        onTap: () => call('ball', {'side': 'b', 'runs': 1}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                GhostButton('Undo', height: 44, radius: 12, onTap: lv['can_undo'] == true ? () => call('undo') : null),
              ],
              if (result != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    result,
                    textAlign: TextAlign.center,
                    style: t(15, w: FontWeight.w700, c: C.green900),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: GhostButton('Undo', onTap: () => call('undo'))),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        f['label'] == 'F' || f['stage'] != 'ko' ? 'Confirm result' : 'Confirm & send to next round',
                        height: 52,
                        radius: 16,
                        fontSize: 15,
                        shadow: false,
                        loading: working,
                        onTap: () => call('confirm'),
                      ),
                    ),
                  ],
                ),
              ],
              if (!cricket && result != null) const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
    _cubit.load();
  }

  Widget _ballBtn(String label, String aria, VoidCallback onTap) {
    final out = label == 'OUT', boundary = label == '4' || label == '6', wide = label == 'WD';
    final bg = out
        ? C.red
        : boundary
        ? C.brand
        : wide
        ? C.amberSoft
        : C.ground;
    final fg = out || boundary
        ? Colors.white
        : wide
        ? C.amber
        : C.ink;
    return Semantics(
      button: true,
      label: aria,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: out || boundary ? BorderSide.none : BorderSide(color: wide ? const Color(0xFFFDE68A) : C.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Text(label, style: d(18, c: fg)),
          ),
        ),
      ),
    );
  }

  List<Widget> _teams(Json tt, bool host) {
    final teams = asList(tt['teams']);
    final pending = tt['pending_payments'] ?? 0;
    final reminded = teams.where((x) => x['paid'] != true).every((x) => x['reminded'] == true) && pending > 0;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Column(
          children: [
            if (pending > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: C.amberSoft, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: t(13, c: const Color(0xFF713F12), h: 1.4),
                          children: [
                            TextSpan(
                              text: '$pending team(s)',
                              style: t(13, w: FontWeight.w700, c: const Color(0xFF713F12)),
                            ),
                            const TextSpan(text: ' yet to pay entry'),
                          ],
                        ),
                      ),
                    ),
                    if (host)
                      GhostButton(
                        reminded ? 'Reminders sent' : 'Remind all',
                        height: 36,
                        radius: 10,
                        fontSize: 12,
                        bg: C.amber,
                        fg: Colors.white,
                        border: Colors.transparent,
                        onTap: reminded ? null : () => _act(_cubit.remindUnpaid, 'Reminders sent'),
                      ),
                  ],
                ),
              ),
            CardBox(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var k = 0; k < teams.length; k++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: k < teams.length - 1
                          ? const BoxDecoration(
                              border: Border(bottom: BorderSide(color: C.divider)),
                            )
                          : null,
                      child: Row(
                        children: [
                          Avatar(teams[k]['initials'], index: k, size: 40, square: true),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(teams[k]['name'], style: t(14, w: FontWeight.w700)),
                                Text(
                                  'Capt. ${teams[k]['captain'].toString().isEmpty ? '—' : teams[k]['captain']} · ${teams[k]['status']}',
                                  style: t(12, c: C.muted),
                                ),
                              ],
                            ),
                          ),
                          teams[k]['paid'] == true
                              ? Pill(
                                  'Paid ${inr(tt['entry_fee'])}',
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                )
                              : Pill(
                                  teams[k]['reminded'] == true ? 'Reminded' : 'Pending',
                                  bg: C.amberSoft,
                                  fg: C.amber,
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                ),
                        ],
                      ),
                    ),
                  if (teams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('No teams yet. Share the link!', style: t(14, c: C.muted)),
                    ),
                ],
              ),
            ),
            if (host && teams.length < (tt['team_count'] as int) && asList(tt['rounds']).isEmpty) ...[
              const SizedBox(height: 10),
              GhostButton('Add a team manually', icon: LucideIcons.plus, height: 46, onTap: _addTeam),
            ],
          ],
        ),
      ),
    ];
  }
}
