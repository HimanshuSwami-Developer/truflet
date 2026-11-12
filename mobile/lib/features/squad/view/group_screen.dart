import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/squad_repository.dart';
import '../cubit/group_cubit.dart';

/// 18 · Group: RSVP, split & invite
class GroupScreen extends StatelessWidget {
  final int id;
  const GroupScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => GroupCubit(id: id, repository: c.read<SquadRepository>()),
    child: const _GroupView(),
  );
}

class _GroupView extends StatefulWidget {
  const _GroupView();
  @override
  State<_GroupView> createState() => _GroupViewState();
}

/// "Copied" and "show all members" are view-only state.
class _GroupViewState extends State<_GroupView> {
  bool copied = false, showAll = false;

  GroupCubit get _cubit => context.read<GroupCubit>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final error = await _cubit.load();
    if (error != null && mounted) toast(context, error);
  }

  Future<void> _rsvp(String resp) async {
    final error = await _cubit.rsvp(resp);
    if (error != null && mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<GroupCubit, Json?>(builder: _build);

  Widget _build(BuildContext context, Json? g) {
    if (g == null) {
      return const Scaffold(body: HeroPageSkeleton(heroHeight: 210, stats: false));
    }
    final gg = g;
    final top = MediaQuery.of(context).padding.top;
    final ng = gg['next_game'] == null ? null : asMap(gg['next_game']);
    final members = asList(gg['members']);
    final link = gg['invite_link'];
    final shareText = 'Join ${gg['name']} on Turflet: https://$link';
    return Scaffold(
      body: RefreshIndicator(
        color: C.brand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            SizedBox(
              height: 210,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Img(gg['image'], fallback: 'cricket'),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.4, 1],
                        colors: [Color(0x59000000), Color(0x1A000000), Color(0xB3000000)],
                      ),
                    ),
                  ),
                  Positioned(top: top + 8, left: 20, child: const BackSquare(translucent: true)),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(gg['name'], style: d(26, c: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          '${gg['sport']['name']} · ${gg['member_count']} members${(gg['area'] ?? '').isNotEmpty ? ' · ${gg['area']}' : ''}',
                          style: t(13, c: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ng != null) _nextGame(ng),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Invite to group', style: d(16, c: C.blueInk)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            link,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t(13, c: C.blueInk),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GhostButton(
                        copied ? 'Copied' : 'Copy',
                        height: 44,
                        radius: 12,
                        fontSize: 13,
                        bg: C.blue,
                        fg: Colors.white,
                        border: Colors.transparent,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: 'https://$link'));
                          setState(() => copied = true);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GhostButton(
                          'WhatsApp',
                          height: 40,
                          radius: 12,
                          fontSize: 13,
                          fg: C.green700,
                          border: Colors.transparent,
                          onTap: () => launchUrl(
                            Uri.parse('https://wa.me/?text=${Uri.encodeComponent(shareText)}'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GhostButton(
                          'Contacts',
                          height: 40,
                          radius: 12,
                          fontSize: 13,
                          fg: C.blueInk,
                          border: Colors.transparent,
                          onTap: () => launchUrl(Uri(scheme: 'sms', queryParameters: {'body': shareText})),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GhostButton(
                          'More',
                          height: 40,
                          radius: 12,
                          fontSize: 13,
                          fg: C.blueInk,
                          border: Colors.transparent,
                          onTap: () => SharePlus.instance.share(ShareParams(text: shareText)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(child: _quick(LucideIcons.volleyball, 'Start a match', 'match')),
                  const SizedBox(width: 10),
                  Expanded(child: _quick(LucideIcons.trophy, 'Host tournament', 'tour')),
                ],
              ),
            ),
            Label('Members · ${members.length}'),
            CardBox(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var k = 0; k < members.length && (showAll || k < 5); k++) _member(members[k], k, k < members.length - 1),
                  if (members.length > 5)
                    InkWell(
                      onTap: () => setState(() => showAll = !showAll),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: C.divider)),
                        ),
                        child: Text(
                          showAll ? 'Show fewer' : 'See all ${members.length} members',
                          style: t(13, w: FontWeight.w700, c: C.brand),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextGame(Json ng) {
    final my = ng['my_rsvp'];
    const opts = [
      ('in', 'I’m in', C.brand, Colors.white),
      ('maybe', 'Maybe', C.amber, C.amberSoft),
      ('out', 'Can’t make it', C.orangeInk, C.orangeSoft),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: shadowCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'NEXT GAME · ${ng['day']}',
                  style: t(11, w: FontWeight.w700, c: C.green700, ls: 0.5),
                ),
              ),
              if (ng['slot_booked'] == true)
                const Pill('Slot booked', bg: C.lime, fg: C.ink, padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: ng['booking_id'] == null ? null : () => context.pushTicket(ng['booking_id']),
            child: Row(
              children: [
                Img(ng['venue_image'], width: 52, height: 52, radius: BorderRadius.circular(14)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ng['venue'], style: t(15, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${ng['time']}${(ng['court'] ?? '').isNotEmpty ? ' · ${ng['court']}' : ''}', style: t(13, c: C.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Are you playing?', style: t(13, w: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < opts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    selected: my == opts[i].$1,
                    button: true,
                    child: GestureDetector(
                      onTap: () => _rsvp(opts[i].$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: my == opts[i].$1 ? (opts[i].$1 == 'in' ? C.brand : opts[i].$4) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: my == opts[i].$1
                              ? (opts[i].$1 == 'in' ? null : Border.all(color: opts[i].$3, width: 2))
                              : Border.all(color: C.line),
                        ),
                        child: Text(
                          opts[i].$2,
                          style: t(
                            13,
                            w: FontWeight.w700,
                            c: my == opts[i].$1 ? (opts[i].$1 == 'in' ? Colors.white : opts[i].$3) : C.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ng['in_count']} in · ${ng['maybe_count']} maybe · split ${inr(ng['total_cost'])}',
                        style: t(12, c: C.muted),
                      ),
                      const SizedBox(height: 2),
                      Text('Your share ${inr(ng['share'])}', style: t(15, w: FontWeight.w700)),
                    ],
                  ),
                ),
                if (my == 'in')
                  GhostButton(
                    'Pay share',
                    height: 40,
                    radius: 12,
                    fontSize: 13,
                    bg: C.brand,
                    fg: Colors.white,
                    border: Colors.transparent,
                    onTap: () => sheet(
                      context,
                      (ctx) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Pay your share', style: d(22)),
                          const SizedBox(height: 8),
                          Text(
                            'Send ${inr(ng['share'])} to the group admin by UPI. In-app split payments are coming soon.',
                            style: t(14, c: C.muted, h: 1.5),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            'Open UPI app',
                            height: 52,
                            onTap: () {
                              Navigator.pop(ctx);
                              launchUrl(
                                Uri.parse(
                                  'upi://pay?am=${ng['share']}&cu=INR&tn=${Uri.encodeComponent(ng['name'] ?? 'Turflet game')}',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                          ),
                        ],
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

  Widget _quick(IconData icon, String label, String type) => Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: shadowSoft),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.pushCreate(type),
        child: SizedBox(
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: C.brand),
              const SizedBox(height: 4),
              Text(label, style: t(13, w: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _member(Json m, int k, bool border) {
    final badge = {
      'Going': (C.mint, C.green700),
      'Maybe': (C.amberSoft, C.amber),
      'Out': (C.orangeSoft, C.orangeInk),
      'No reply': (C.chip, C.muted),
    }[m['status']];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: border
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: C.divider)),
            )
          : null,
      child: Row(
        children: [
          Avatar(m['initials'], index: k, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['name'], style: t(14, w: FontWeight.w700)),
                Text(m['meta'] ?? '', style: t(12, c: C.muted)),
              ],
            ),
          ),
          if (badge != null)
            Pill(m['status'], bg: badge.$1, fg: badge.$2, padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
        ],
      ),
    );
  }
}
