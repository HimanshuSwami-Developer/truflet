import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/session/app_cubit.dart';
import '../../../app/session/app_state.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/lobby_repository.dart';
import '../cubit/lobbies_cubit.dart';
import '../widgets/lobby_widgets.dart';
import 'lobbies_screen.dart';

/// Matches tab: the matches I host or play in, my pending requests, and past matches.
class MyMatchesScreen extends StatelessWidget {
  const MyMatchesScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => MyMatchesCubit(repository: c.read<LobbyRepository>())..load(),
    // refresh whenever the player switches to this tab
    child: BlocListener<AppCubit, AppState>(
      listenWhen: (prev, cur) => cur.tab == AppTab.matches && prev.tab != AppTab.matches,
      listener: (context, _) => context.read<MyMatchesCubit>().reload(),
      child: const _MyMatchesView(),
    ),
  );
}

class _MyMatchesView extends StatefulWidget {
  const _MyMatchesView();
  @override
  State<_MyMatchesView> createState() => _MyMatchesViewState();
}

class _MyMatchesViewState extends State<_MyMatchesView> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final cubit = context.read<MyMatchesCubit>();
    final app = context.watch<AppCubit>().state;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 12, 20, 0),
          child: Row(
            children: [
              Expanded(child: Text('Matches', style: d(26, ls: -0.4))),
              GhostButton(
                'Find lobbies',
                icon: LucideIcons.search,
                height: 40,
                radius: 12,
                fontSize: 13,
                onTap: () async {
                  await context.pushLobbies(LobbiesArgs(areaId: app.areaId, cityName: app.cityName));
                  cubit.load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: DataBuilder<MyMatchesCubit, Json>(
            skeleton: const BookingCardsSkeleton(),
            builder: (context, data) {
              final lists = [asList(data['upcoming']), asList(data['requests']), asList(data['past'])];
              final items = lists[tab];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Segmented(
                      labels: const ['Upcoming', 'Requests', 'Past'],
                      counts: [for (final l in lists) l.length],
                      index: tab,
                      onChanged: (i) => setState(() => tab = i),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      color: C.brand,
                      onRefresh: cubit.load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          if (items.isEmpty) _empty(context),
                          for (final g in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _MatchTile(
                                lobby: g,
                                onTap: () async {
                                  await openLobby(context, g, onChanged: cubit.load);
                                  cubit.load();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) => switch (tab) {
    1 => const EmptyNote(
      icon: LucideIcons.messagesSquare,
      title: 'No invites or requests',
      body: 'Friends\' invites to their matches, and your requests to join open lobbies, show up here.',
    ),
    2 => const EmptyNote(icon: LucideIcons.history, title: 'No past matches', body: 'Matches you played show up here.'),
    _ => EmptyNote(
      icon: LucideIcons.usersRound,
      title: 'No matches yet',
      body: 'Pick a slot at any venue, then create a group or join a lobby solo.',
      action: PrimaryButton('Explore venues', height: 48, onTap: () => context.read<AppCubit>().setTab(AppTab.explore)),
    ),
  };
}

class _MatchTile extends StatelessWidget {
  final Json lobby;
  final VoidCallback onTap;
  const _MatchTile({required this.lobby, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = lobby;
    final role = g['my_role'];
    final (roleLabel, bg, fg) = switch (role) {
      'host' => ('Hosting', C.mint, C.green700),
      'member' => ('Playing', C.blueSoft, C.blue),
      'requested' => ('Requested', C.amberSoft, C.amber),
      'invited' => ('Invited you', C.coralSoft, C.orangeInk),
      _ => ('', C.chip, C.muted),
    };
    final alert = role == 'host' && (g['alert'] ?? '').toString().isNotEmpty;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: shadowSoft,
            border: alert ? Border.all(color: C.orange, width: 1.5) : null,
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (roleLabel.isNotEmpty) ...[Pill(roleLabel, bg: bg, fg: fg), const SizedBox(width: 6)],
                  SlotStatePill(g),
                  const Spacer(),
                  Text('${g['paid_count']}/${g['capacity']} paid', style: t(12, w: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              Text('${g['date_label']} · ${g['time_label']}', style: d(17)),
              Text(
                '${g['sport']['name']} · ${g['venue']['name']} · ${g['court']['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t(13, c: C.muted),
              ),
              const SizedBox(height: 10),
              FillBar(taken: (g['taken'] ?? 0) as int, capacity: (g['capacity'] ?? 1) as int),
              if (alert) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(LucideIcons.triangleAlert, size: 14, color: C.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        g['alert'] == 'slot_taken'
                            ? 'Your slot was booked by another group — action needed'
                            : 'Kickoff soon and the pool is short — action needed',
                        style: t(12, w: FontWeight.w600, c: C.orangeInk),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
