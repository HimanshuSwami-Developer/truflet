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
import '../../../data/repositories/lobby_repository.dart';
import '../../auth/auth_guard.dart';
import '../cubit/lobbies_cubit.dart';
import '../widgets/lobby_widgets.dart';

/// 3 · Open Lobbies (Solo view): compare groups looking for players and request to join one.
class LobbiesScreen extends StatelessWidget {
  final LobbiesArgs args;
  const LobbiesScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => LobbiesCubit(
      args: args,
      repository: c.read<LobbyRepository>(),
      areaId: c.read<AppCubit>().state.areaId,
    )..load(),
    child: _LobbiesView(args: args),
  );
}

/// Opens the right place for a lobby: the Match Room, my request thread, or the request sheet.
Future<void> openLobby(BuildContext context, Json lobby, {VoidCallback? onChanged}) async {
  final role = lobby['my_role'];
  if (role == 'host' || role == 'member') return context.pushMatch(lobby['id']);
  if (role == 'requested' && lobby['my_request_id'] != null) {
    return context.pushRequestThread(lobby['id'], lobby['my_request_id']);
  }
  if (role == 'declined' || (lobby['spots_left'] ?? 0) <= 0) return;
  if (!await requireProfile(context) || !context.mounted) return;
  final req = await sheet<Json>(context, (_) => _RequestSheet(lobby: lobby));
  onChanged?.call();
  if (req != null && context.mounted) {
    await context.pushRequestThread(lobby['id'], req['id']);
    onChanged?.call();
  }
}

class _LobbiesView extends StatelessWidget {
  final LobbiesArgs args;
  const _LobbiesView({required this.args});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final cubit = context.read<LobbiesCubit>();
    final city = context.watch<AppCubit>().state.cityName;
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
                      Text(args.isCity ? 'Open lobbies in ${args.cityName.isEmpty ? city : args.cityName}' : 'Join solo', style: d(20)),
                      Text(
                        args.subtitle.isNotEmpty
                            ? args.subtitle
                            : args.isCity
                            ? 'Groups looking for players'
                            : '${args.venue!['name']} · ${args.venue!['area']}',
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
            child: DataBuilder<LobbiesCubit, List<Json>>(
              skeleton: const ListSkeleton(count: 4, leading: 48),
              builder: (context, lobbies) => RefreshIndicator(
                color: C.brand,
                onRefresh: cubit.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: C.limeSoft, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.shieldCheck, size: 18, color: C.green700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Request a spot and chat 1-on-1 with the host. Once approved you enter the Match Room and '
                              'pay your share into escrow — never to the host directly.',
                              style: t(13, c: C.green900, h: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (lobbies.isEmpty)
                      EmptyNote(
                        icon: LucideIcons.userPlus,
                        title: 'No open lobbies here yet',
                        body: args.isCity
                            ? 'Check back soon, or create a group from any venue and open it to solo players.'
                            : 'Go back and tap “Create a group” to start one — solo players nearby can join.',
                      ),
                    for (final g in lobbies)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LobbyCard(
                          lobby: g,
                          showVenue: args.isCity || args.date == null,
                          onTap: () => openLobby(context, g, onChanged: cubit.load),
                          onAction: () => openLobby(context, g, onChanged: cubit.load),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Request to join": optional intro for the host's screening thread.
class _RequestSheet extends StatefulWidget {
  final Json lobby;
  const _RequestSheet({required this.lobby});
  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final note = TextEditingController();
  bool busy = false;

  Future<void> _send() async {
    setState(() => busy = true);
    try {
      final r = await context.read<LobbyRepository>().requestToJoin(widget.lobby['id'], note.text.trim());
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.lobby;
    final split = (g['per_head'] ?? 0) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Request to join', style: d(22)),
        const SizedBox(height: 6),
        Text('${g['sport']['name']} · ${g['date_label']} · ${g['time_label']}', style: t(14, c: C.muted)),
        const SizedBox(height: 14),
        CardBox(
          shadow: null,
          border: Border.all(color: C.line),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _step(LucideIcons.messageCircle, 'A private chat opens with ${g['host']['name']}. The squad chat stays hidden.'),
              _step(LucideIcons.userCheck, 'The host approves or declines after checking your attendance score.'),
              _step(
                split ? LucideIcons.timer : LucideIcons.circleCheck,
                split
                    ? 'Once approved, pay your ${inr(g['per_head'])} share within 15 minutes.'
                    : 'The host covers the slot — you play free once approved.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: C.ground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.line),
          ),
          child: TextField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            style: t(14),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Say hi — position, skill level… (optional)',
              hintStyle: t(14, c: C.muted),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton('Send request', loading: busy, onTap: _send),
      ],
    );
  }

  Widget _step(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: C.green700),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: t(13, h: 1.4))),
      ],
    ),
  );
}
