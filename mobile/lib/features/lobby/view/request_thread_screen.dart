import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/lobby_repository.dart';
import '../cubit/request_thread_cubit.dart';
import '../widgets/chat.dart';
import '../widgets/lobby_widgets.dart';
import 'match_room_screen.dart';

/// 5 · Host Request Screening: a private 1-on-1 thread between a solo player and the host.
/// Unapproved players never see the squad chat or phone numbers.
class RequestThreadScreen extends StatelessWidget {
  final int lobbyId, requestId;
  const RequestThreadScreen({super.key, required this.lobbyId, required this.requestId});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => RequestThreadCubit(lobbyId: lobbyId, requestId: requestId, repository: c.read<LobbyRepository>())..load(),
    child: const _ThreadView(),
  );
}

class _ThreadView extends StatefulWidget {
  const _ThreadView();
  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final scroll = ScrollController();
  bool busy = false;

  RequestThreadCubit get _cubit => context.read<RequestThreadCubit>();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _decide(String action) async {
    setState(() => busy = true);
    try {
      await _cubit.decide(action);
      if (!mounted) return;
      toast(
        context,
        switch (action) {
          'approve' => 'Approved — they\'re in the Match Room now.',
          'decline' => 'Request declined.',
          _ => 'Request withdrawn.',
        },
      );
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<RequestThreadCubit, RequestThreadState>(
    builder: (context, st) {
      final r = st.request;
      final top = MediaQuery.of(context).padding.top;
      if (r == null) {
        return Scaffold(
          body: SafeArea(
            child: st.error != null
                ? Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(padding: EdgeInsets.all(20), child: BackSquare()),
                      ),
                      Expanded(child: ErrorRetry(st.error!, onRetry: _cubit.load)),
                    ],
                  )
                : const ListSkeleton(count: 5),
          ),
        );
      }
      final lobby = asMap(r['lobby']);
      final player = asMap(r['player']);
      final pending = st.status == 'pending';
      return Scaffold(
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, top + 8, 16, 8),
              child: Row(
                children: [
                  const BackSquare(),
                  const SizedBox(width: 12),
                  if (st.isHost) ...[
                    Avatar(player['initials'] ?? '', size: 40, index: (player['id'] ?? 0) as int),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          st.isHost ? player['name'] ?? '' : 'Chat with ${lobby['host']['name']}',
                          style: d(18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          st.isHost ? attendanceLine(player) : 'Private request · ${reliability(asMap(lobby['host']))}',
                          style: t(12, c: C.green700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _context(st, lobby, player),
            Expanded(
              child: ChatList(
                messages: st.messages,
                controller: scroll,
                emptyText: st.isHost ? 'Ask them anything before approving' : 'Introduce yourself to the host',
              ),
            ),
            if (pending)
              Composer(
                safeBottom: false,
                hint: st.isHost ? 'Reply privately…' : 'Message the host privately…',
                onSend: (body) async {
                  final err = await _cubit.send(body);
                  if (err != null && mounted) toast(this.context, err);
                  return err == null;
                },
              ),
            _actions(st, lobby),
          ],
        ),
      );
    },
  );

  /// Host sees the player's stats; the requester sees the match they asked to join and the status.
  Widget _context(RequestThreadState st, Json lobby, Json player) {
    final status = st.status;
    final (label, bg, fg) = switch (status) {
      'approved' => ('Approved', C.mint, C.green700),
      'declined' => ('Declined', C.redSoft, C.redInk),
      'withdrawn' => ('Withdrawn', C.chip, C.muted),
      _ => ('Waiting for host', C.amberSoft, C.amber),
    };
    final sports = asList(player['sports']);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: shadowSoft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SportPill(asMap(lobby['sport'])),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${lobby['date_label']} · ${lobby['time_label']}',
                  style: t(13, w: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Pill(label, bg: bg, fg: fg),
            ],
          ),
          if (st.isHost) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Stat('Games', '${player['played'] ?? 0}')),
                const SizedBox(width: 8),
                Expanded(child: Stat('Attendance', player['score'] == null ? 'New' : '${player['score']}%')),
                const SizedBox(width: 8),
                Expanded(child: Stat('Drop-offs', '${player['drop_offs'] ?? 0}')),
              ],
            ),
            if (sports.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final s in sports) Pill('${s['name']} · ${s['level']}', bg: C.chip, fg: C.mutedInk)],
              ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Text(
              '${lobby['venue']['name']} · ${lobby['taken']}/${lobby['capacity']} joined · '
              '${(lobby['per_head'] ?? 0) > 0 ? 'your share ₹${lobby['per_head']}' : 'free (host pays)'}',
              style: t(12, c: C.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(RequestThreadState st, Json lobby) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final status = st.status;
    Widget bar(List<Widget> children) => Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: Row(children: children),
    );
    if (st.isHost && status == 'pending') {
      return bar([
        Expanded(
          child: GhostButton(
            'Decline',
            icon: LucideIcons.x,
            height: 50,
            fg: C.redInk,
            border: C.redSoft,
            onTap: busy ? null : () => _decide('decline'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: PrimaryButton(
            'Approve to match chat',
            height: 50,
            radius: 16,
            fontSize: 14,
            shadow: false,
            loading: busy,
            onTap: () => _decide('approve'),
          ),
        ),
      ]);
    }
    if (!st.isHost && status == 'pending') {
      return bar([
        Expanded(
          child: GhostButton('Withdraw request', height: 46, onTap: busy ? null : () => _decide('withdraw')),
        ),
      ]);
    }
    if (!st.isHost && status == 'approved') {
      return bar([
        Expanded(
          child: PrimaryButton(
            (lobby['per_head'] ?? 0) > 0 ? 'Open Match Room & pay' : 'Open Match Room',
            height: 52,
            radius: 16,
            shadow: false,
            trailing: const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18),
            onTap: () => context.replaceWithMatch(lobby['id']),
          ),
        ),
      ]);
    }
    return const SizedBox.shrink();
  }
}
