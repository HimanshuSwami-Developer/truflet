import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/community_repository.dart';
import '../cubit/group_detail_cubit.dart';

/// A group: invite people, see members and upcoming group games. Pops `true` after leaving.
class GroupScreen extends StatelessWidget {
  final int id;
  const GroupScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => GroupDetailCubit(id: id, repository: c.read<CommunityRepository>())..load(),
    child: const _GroupView(),
  );
}

class _GroupView extends StatefulWidget {
  const _GroupView();
  @override
  State<_GroupView> createState() => _GroupViewState();
}

/// The contact field and "Copied" label are view-only state.
class _GroupViewState extends State<_GroupView> {
  final contact = TextEditingController();
  bool adding = false, copied = false;

  GroupDetailCubit get _cubit => context.read<GroupDetailCubit>();

  Future<void> _add() async {
    if (contact.text.trim().isEmpty) return;
    setState(() => adding = true);
    try {
      final message = await _cubit.addMember(contact.text);
      contact.clear();
      if (mounted) toast(context, message);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  Future<void> _remove(Json m) async {
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Remove ${m['name']}?', style: d(22)),
          const SizedBox(height: 16),
          PrimaryButton('Remove from group', height: 52, color: C.redInk, shadow: false, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _cubit.removeMember(m['id']);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _leave() async {
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Leave this group?', style: d(22)),
          const SizedBox(height: 8),
          Text(
            "You'll stop getting invites for its games. You can rejoin with the invite code.",
            style: t(14, c: C.muted, h: 1.5),
          ),
          const SizedBox(height: 16),
          PrimaryButton('Leave group', height: 52, color: C.redInk, shadow: false, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _cubit.leave();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DataBuilder<GroupDetailCubit, Json>(
      skeleton: const HeroPageSkeleton(heroHeight: 150, stats: false),
      builder: (context, g) => _body(g),
    ),
  );

  Widget _body(Json g) {
    final top = MediaQuery.of(context).padding.top;
    final members = asList(g['members']);
    final pending = (g['pending_invites'] as List? ?? const []).cast<String>();
    final upcoming = asList(g['upcoming']);
    final admin = g['is_admin'] == true;
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _cubit.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 22),
            decoration: const BoxDecoration(
              color: C.blueSoft,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackSquare(),
                const SizedBox(height: 14),
                Text(g['name'] ?? '', style: d(26, c: C.blueInk)),
                const SizedBox(height: 4),
                Text('${members.length} member${members.length == 1 ? '' : 's'}', style: t(13, c: C.blueInk)),
              ],
            ),
          ),
          // invite
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: shadowSoft),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const H2('Invite people', size: 16),
                const SizedBox(height: 10),
                Text('Share the invite code', style: t(12, c: C.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(12)),
                        child: Text(g['invite_code'] ?? '', style: d(20, ls: 4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GhostButton(
                      copied ? 'Copied' : 'Copy',
                      height: 46,
                      radius: 12,
                      fontSize: 13,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: g['invite_code'] ?? ''));
                        setState(() => copied = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    GhostButton(
                      'Share',
                      icon: LucideIcons.share2,
                      height: 46,
                      radius: 12,
                      fontSize: 13,
                      bg: C.blue,
                      fg: Colors.white,
                      border: Colors.transparent,
                      onTap: () => SharePlus.instance.share(ShareParams(text: g['share_text'] ?? '')),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Or add by email / mobile number', style: t(12, c: C.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: C.ground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: C.line),
                        ),
                        child: TextField(
                          controller: contact,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          style: t(14),
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'friend@email.com or 98765 43210',
                            hintStyle: t(14, c: C.muted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: PrimaryButton(
                        'Add',
                        height: 46,
                        radius: 12,
                        fontSize: 14,
                        shadow: false,
                        loading: adding,
                        onTap: _add,
                      ),
                    ),
                  ],
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Invited — joins when they sign in', style: t(12, c: C.muted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final p in pending) Pill(p, bg: C.amberSoft, fg: C.amber)],
                  ),
                ],
              ],
            ),
          ),
          if (upcoming.isNotEmpty) ...[
            const Label('Upcoming games'),
            for (final u in upcoming)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: u['is_mine'] == true ? () => context.pushTicket(u['booking_id']) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(LucideIcons.calendar, size: 18, color: C.green700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${u['sport']} at ${u['venue']}', style: t(14, w: FontWeight.w700)),
                                Text('${u['when']} · booked by ${u['booked_by']}', style: t(12, c: C.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          Label('Members · ${members.length}'),
          CardBox(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var k = 0; k < members.length; k++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: k < members.length - 1
                        ? const BoxDecoration(
                            border: Border(bottom: BorderSide(color: C.divider)),
                          )
                        : null,
                    child: Row(
                      children: [
                        Avatar(members[k]['initials'], index: k, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${members[k]['name']}${members[k]['is_me'] == true ? ' (you)' : ''}',
                            style: t(14, w: FontWeight.w700),
                          ),
                        ),
                        if (members[k]['role'] == 'admin') const Pill('Admin', bg: C.chip, fg: C.mutedInk),
                        if (admin && members[k]['is_me'] != true)
                          SquareIconButton(
                            LucideIcons.x,
                            size: 34,
                            iconSize: 16,
                            label: 'Remove ${members[k]['name']}',
                            onTap: () => _remove(members[k]),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: GhostButton('Leave group', fg: C.redInk, border: const Color(0xFFFECACA), onTap: _leave),
          ),
        ],
      ),
    );
  }
}
