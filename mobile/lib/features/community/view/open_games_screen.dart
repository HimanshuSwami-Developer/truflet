import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/community_repository.dart';
import '../../auth/auth_guard.dart';
import '../cubit/open_games_cubit.dart';

/// Play solo with strangers: open games at this venue, or start a new one.
class OpenGamesScreen extends StatelessWidget {
  final OpenGamesArgs args;
  const OpenGamesScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => OpenGamesCubit(venueId: args.venue['id'], repository: c.read<CommunityRepository>())..load(),
    child: _OpenGamesView(args: args),
  );
}

class _OpenGamesView extends StatelessWidget {
  final OpenGamesArgs args;
  const _OpenGamesView({required this.args});

  Future<void> _startNew(BuildContext context) async {
    await context.pushSlotBooking(SlotBookingArgs(venue: args.venue, initialSportId: args.sportId, openGame: true));
    if (context.mounted) context.read<OpenGamesCubit>().load();
  }

  Future<void> _join(BuildContext context, Json g) async {
    if (!await requireProfile(context) || !context.mounted) return;
    final cubit = context.read<OpenGamesCubit>();
    final joined = await sheet<bool>(
      context,
      (ctx) => BlocProvider.value(
        value: cubit,
        child: _JoinSheet(game: g),
      ),
    );
    if (joined == true && context.mounted) toast(context, "You're in! It's in My bookings.");
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final venue = args.venue;
    return Scaffold(
      body: Column(
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
                      Text('Open games', style: d(20)),
                      Text(
                        '${venue['name']} · ${venue['area']}',
                        style: t(13, c: C.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DataBuilder<OpenGamesCubit, List<Json>>(
              skeleton: const ListSkeleton(count: 4, leading: 48),
              builder: (context, games) => RefreshIndicator(
                color: C.brand,
                onRefresh: context.read<OpenGamesCubit>().load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: C.limeSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.info, size: 18, color: C.green700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Join a game other players opened and pay just your share — or start your own and '
                              "let strangers fill the spots. Each player's share is added to the host's Turflet balance.",
                              style: t(13, c: C.green900, h: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (games.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.userPlus, size: 40, color: C.muted),
                            const SizedBox(height: 12),
                            Text('No open games here yet', style: d(18)),
                            const SizedBox(height: 6),
                            Text(
                              'Start one and players nearby can join.',
                              textAlign: TextAlign.center,
                              style: t(14, c: C.muted),
                            ),
                          ],
                        ),
                      ),
                    for (final g in games)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GameCard(game: g, onJoin: () => _join(context, g)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: C.line)),
            ),
            child: PrimaryButton(
              'Start a new game',
              trailing: const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18),
              onTap: () => _startNew(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final Json game;
  final VoidCallback onJoin;
  const _GameCard({required this.game, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final players = asList(g['players']);
    final full = (g['spots_left'] ?? 0) <= 0;
    final total = g['total_players'] as int, joined = g['joined_count'] as int;
    final mine = g['is_host'] == true, joinedByMe = g['joined'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: shadowCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SportPill(asMap(g['sport'])),
              const SizedBox(width: 8),
              Expanded(
                child: Text(g['court'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t(12, c: C.muted)),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: inr(g['share']),
                      style: d(18, c: C.brand),
                    ),
                    TextSpan(
                      text: ' /player',
                      style: t(12, c: C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${g['date_label']} · ${g['time_label']}', style: d(17)),
          const SizedBox(height: 2),
          Text('Hosted by ${g['host']}', style: t(13, c: C.muted)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : joined / total,
              minHeight: 6,
              backgroundColor: C.segment,
              color: C.brand,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 26.0 + 16 * (players.length - 1).clamp(0, 4),
                height: 26,
                child: Stack(
                  children: [
                    for (var k = 0; k < players.length && k < 5; k++)
                      Positioned(
                        left: k * 16.0,
                        child: Avatar(players[k]['initials'], index: k, size: 26, ring: true),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$joined of $total in · ${full ? 'full' : '${g['spots_left']} spot${g['spots_left'] == 1 ? '' : 's'} left'}',
                  style: t(12, c: C.muted),
                ),
              ),
              if (mine)
                const Pill('Your game', bg: C.chip, fg: C.mutedInk)
              else if (joinedByMe)
                const Pill("You're in")
              else
                GhostButton(
                  full ? 'Full' : 'Join',
                  height: 38,
                  radius: 12,
                  fontSize: 13,
                  bg: full ? C.chip : C.brand,
                  fg: full ? C.muted : Colors.white,
                  border: Colors.transparent,
                  onTap: full ? null : onJoin,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Confirm & pay my share.
class _JoinSheet extends StatefulWidget {
  final Json game;
  const _JoinSheet({required this.game});
  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  String method = 'upi';
  final upi = TextEditingController();
  bool busy = false;

  Future<void> _pay() async {
    setState(() => busy = true);
    try {
      await context.read<OpenGamesCubit>().join(widget.game['id'], method: method, upiId: upi.text.trim());
      if (!mounted) return;
      context.read<AppCubit>().refreshMe(); // wallet balance changed
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final wallet = context.watch<AppCubit>().state.user?['wallet_balance'] ?? 0;
    Widget option(String id, String title, String sub, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Choice(
        selected: method == id,
        filled: false,
        selBg: Colors.white,
        selWidth: 2,
        height: 60,
        onTap: () => setState(() => method = id),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: C.green700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(14, w: FontWeight.w600)),
                  Text(sub, style: t(12, c: C.muted)),
                ],
              ),
            ),
            RadioDot(method == id),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Join this game', style: d(22)),
        const SizedBox(height: 6),
        Text('${g['sport']['name']} · ${g['date_label']} · ${g['time_label']} · ${g['court']}', style: t(14, c: C.muted)),
        const SizedBox(height: 16),
        PriceRow('Your share', inr(g['share']), bold: true),
        const SizedBox(height: 6),
        Text('You can leave and get it back up to 6 hours before the game.', style: t(12, c: C.muted)),
        const SizedBox(height: 16),
        option('upi', 'UPI', 'Pay from any UPI app', LucideIcons.chevronsRight),
        if (method == 'upi')
          Container(
            height: 46,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.ground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: TextField(
              controller: upi,
              keyboardType: TextInputType.emailAddress,
              style: t(14),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'yourname@bank',
                hintStyle: t(14, c: C.muted),
              ),
            ),
          ),
        option('wallet', 'Turflet balance', 'Balance ${inr(wallet)}', LucideIcons.wallet),
        const SizedBox(height: 8),
        PrimaryButton('Pay ${inr(g['share'])} & join', loading: busy, onTap: _pay),
      ],
    );
  }
}
