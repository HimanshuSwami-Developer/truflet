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
import '../../../data/repositories/play_repository.dart';
import '../cubit/play_cubit.dart';

/// 14 · Play hub
class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => PlayCubit(repository: c.read<PlayRepository>())..load(),
    // refresh whenever the player switches to this tab
    child: BlocListener<AppCubit, AppState>(
      listenWhen: (prev, cur) => cur.tab == 2 && prev.tab != 2,
      listener: (context, _) => context.read<PlayCubit>().load(),
      child: const _PlayView(),
    ),
  );
}

class _PlayView extends StatefulWidget {
  const _PlayView();
  @override
  State<_PlayView> createState() => _PlayViewState();
}

class _PlayViewState extends State<_PlayView> with SingleTickerProviderStateMixin {
  PlayCubit get _cubit => context.read<PlayCubit>();
  late final blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    blink.dispose();
    super.dispose();
  }

  Future<void> _register(Json o) async {
    if (o['registered'] == true) {
      await _cubit.unregister(o['id']);
      return;
    }
    final ctl = TextEditingController(
      text: "${(context.read<AppCubit>().state.user?['name'] ?? 'My').toString().split(' ').first}'s XI",
    );
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Register for ${o['name']}', style: d(20)),
          const SizedBox(height: 6),
          Text('Entry ${o['fee_label']} · you are the captain.', style: t(13, c: C.muted)),
          const SizedBox(height: 14),
          Text('Team name', style: t(13, w: FontWeight.w600)),
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
              controller: ctl,
              style: t(15),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton('Register team', height: 52, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    try {
      await _cubit.register(o['id'], ctl.text);
      if (mounted) toast(context, 'Registered! Pay the entry from the tournament page.');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayCubit, PlayState>(builder: _build);

  Widget _build(BuildContext context, PlayState st) {
    final data = st.data, error = st.error, tab = st.tab;
    final top = MediaQuery.of(context).padding.top;
    final live = data?['live'];
    final items = asList(data?[['upcoming', 'hosting', 'past'][tab]]);
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _cubit.load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, top + 12, 0, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Play', style: d(28, ls: -0.5)),
                const SizedBox(height: 4),
                Text('Organise matches & run tournaments', style: t(13, c: C.muted)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: _hero(
                    'ball',
                    'Quick match',
                    'Book, split teams, invite',
                    const [Color(0x591D4ED8), Color(0xE61E3A8A)],
                    Colors.white,
                    C.blue,
                    LucideIcons.volleyball,
                    C.blueSoft,
                    () async {
                      await context.pushCreate('match');
                      _cubit.load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _hero(
                    'cricket',
                    'Host tournament',
                    'Fixtures auto-made',
                    const [Color(0x5916803C), Color(0xEB0F5E2C)],
                    C.lime,
                    C.ink,
                    LucideIcons.trophy,
                    C.mint,
                    () async {
                      await context.pushCreate('tour');
                      _cubit.load();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (live != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () async {
                    await context.pushTournament(live['tournament_id']);
                    _cubit.load();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFFCA5A5), width: 2),
                      boxShadow: shadowCard,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            FadeTransition(
                              opacity: blink,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: C.red, shape: BoxShape.circle),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "LIVE · YOU'RE HOSTING",
                              style: t(11, w: FontWeight.w700, c: C.redInk, ls: 0.5),
                            ),
                            const Spacer(),
                            Text(live['round'] ?? '', style: t(12, c: C.muted)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(live['tournament'], style: d(16)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(live['a'], style: t(14, w: FontWeight.w700)),
                            ),
                            Text(live['a_score'] ?? '', style: t(14, w: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(live['b'], style: t(14, c: C.muted)),
                            ),
                            Text(live['b_score'] ?? '', style: t(14, c: C.muted)),
                          ],
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.only(top: 10),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: C.divider)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(live['summary'] ?? '', style: t(12, c: C.muted)),
                              ),
                              Text(
                                'Manage →',
                                style: t(13, w: FontWeight.w700, c: C.brand),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Segmented(labels: const ['Upcoming', 'Hosting', 'Past'], index: tab, onChanged: _cubit.selectTab),
          ),
          if (error != null) ErrorRetry(error, onRetry: _cubit.load),
          if (data == null && error == null)
            const ListSkeleton(count: 3, leading: 44, padding: EdgeInsets.fromLTRB(20, 12, 20, 0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              children: [
                for (final g in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _game(g)),
                if (data != null && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      ['Nothing planned. Start a quick match!', 'You are not hosting anything yet.', 'No past games yet.'][tab],
                      style: t(14, c: C.muted),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 10), child: H2('Tournaments near you')),
          SizedBox(
            height: 282,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              itemCount: asList(data?['open_tournaments']).length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _open(asList(data?['open_tournaments'])[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(
    String img,
    String title,
    String sub,
    List<Color> grad,
    Color iconBg,
    Color iconFg,
    IconData icon,
    Color subColor,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      height: 132,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/$img.jpg', fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: grad),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, size: 18, color: iconFg),
                  ),
                  const SizedBox(height: 8),
                  Text(title, style: d(16, c: Colors.white)),
                  Text(sub, style: t(12, c: subColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _game(Json g) {
    final sp = asMap(g['sport']);
    final badge =
        {
          'Match': (C.blueSoft, const Color(0xFF1E40AF)),
          'Live': (C.redSoft, C.redInk),
          'Draft': (C.chip, C.muted),
          'Open': (C.mint, C.green700),
          'Won': (C.amberSoft, C.amber),
          'Lost': (C.chip, C.muted),
          'Played': (C.chip, C.muted),
        }[g['status']] ??
        (C.chip, C.muted);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          if (g['kind'] == 'tournament') {
            await context.pushTournament(g['id']);
          } else if (g['group_id'] != null) {
            await context.pushGroup(g['group_id']);
          }
          _cubit.load();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: shadowSoft, color: Colors.white),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: hex(sp['bg'], C.mint), borderRadius: BorderRadius.circular(14)),
                child: Icon(
                  g['kind'] == 'tournament' ? LucideIcons.trophy : LucideIcons.volleyball,
                  size: 22,
                  color: hex(sp['fg']),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g['title'], style: t(14, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      g['meta'],
                      style: t(12, c: C.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Pill(g['status'], bg: badge.$1, fg: badge.$2, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _open(Json o) {
    final on = o['registered'] == true;
    final filled = o['filled'] as int, total = o['team_count'] as int;
    return Container(
      width: 240,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: shadowCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushTournament(o['id']),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Img(o['image']),
                  Positioned(left: 10, top: 10, child: SportPill(asMap(o['sport']))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(o['name'], style: d(15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(
                    o['when'],
                    style: t(12, c: C.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: t(12),
                            children: [
                              const TextSpan(text: 'Entry '),
                              TextSpan(
                                text: o['fee_label'],
                                style: t(12, w: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          style: t(12),
                          children: [
                            const TextSpan(text: 'Prize '),
                            TextSpan(
                              text: inr(o['prize_pool']),
                              style: t(12, w: FontWeight.w700, c: C.green700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : filled / total,
                      minHeight: 6,
                      backgroundColor: C.segment,
                      color: C.brand,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${o['spots_left']} spots left', style: t(12, c: C.muted)),
                      ),
                      SizedBox(
                        height: 34,
                        child: Material(
                          color: on ? C.mint : C.brand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: on ? const BorderSide(color: C.brand) : BorderSide.none,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _register(o),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Center(
                                child: Text(
                                  on ? 'Registered' : 'Register',
                                  style: t(12, w: FontWeight.w700, c: on ? C.green700 : Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
