import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../app/session/app_state.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/squad_repository.dart';
import '../cubit/squad_cubit.dart';

/// 17 · Squad: groups & friends
class SquadScreen extends StatelessWidget {
  const SquadScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => SquadCubit(repository: c.read<SquadRepository>()),
    child: const _SquadView(),
  );
}

class _SquadView extends StatefulWidget {
  const _SquadView();
  @override
  State<_SquadView> createState() => _SquadViewState();
}

/// "Copied" on the invite code is view-only state.
class _SquadViewState extends State<_SquadView> {
  bool copied = false;

  SquadCubit get _cubit => context.read<SquadCubit>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final error = await _cubit.load();
    if (error != null && mounted) toast(context, error);
  }

  Future<void> _createGroup() async {
    final app = context.read<AppCubit>();
    try {
      await app.ensureBasics();
    } catch (e) {
      if (mounted) toast(context, e.toString());
      return;
    }
    if (!mounted) return;
    final s = app.state;
    if (s.sports.isEmpty) {
      toast(context, 'No sports are set up yet.');
      return;
    }
    final ctl = TextEditingController();
    var sportId = s.sports.isNotEmpty ? s.sports.first['id'] : null;
    final ok = await sheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New group', style: d(22)),
              const SizedBox(height: 14),
              Text('Group name', style: t(13, w: FontWeight.w600)),
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
                  autofocus: true,
                  style: t(15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. Weekend Warriors',
                    hintStyle: t(15, c: C.muted),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Main sport', style: t(13, w: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sp in s.sports)
                    GestureDetector(
                      onTap: () => set(() => sportId = sp['id']),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sportId == sp['id'] ? hex(sp['bg']) : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: sportId == sp['id'] ? hex(sp['fg']) : C.line,
                            width: sportId == sp['id'] ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          sp['name'],
                          style: t(13, w: FontWeight.w600, c: sportId == sp['id'] ? hex(sp['fg']) : C.ink),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('After creating, share the group link so friends can join in one tap.', style: t(12, c: C.muted)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: GhostButton('Cancel', fontSize: 15, onTap: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      'Create group',
                      height: 52,
                      radius: 16,
                      fontSize: 15,
                      shadow: false,
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await _cubit.createGroup(ctl.text.trim(), sportId);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => BlocListener<AppCubit, AppState>(
    // refresh whenever the player switches to this tab
    listenWhen: (prev, cur) => cur.tab == 3 && prev.tab != 3,
    listener: (context, _) => _load(),
    child: BlocBuilder<SquadCubit, SquadState>(builder: _build),
  );

  Widget _build(BuildContext context, SquadState st) {
    final s = context.watch<AppCubit>().state;
    final tab = st.tab, loaded = st.loaded, requests = st.requests;
    final code = s.user?['referral_code'] ?? '';
    final reward = s.config['referral_reward'] ?? 50;
    final top = MediaQuery.of(context).padding.top;
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, top + 12, 0, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Squad', style: d(28, ls: -0.5)),
                      const SizedBox(height: 4),
                      Text('Your groups, friends & players nearby', style: t(13, c: C.muted)),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Create group',
                  child: GestureDetector(
                    onTap: _createGroup,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: C.brand,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: shadowBrandSm,
                      ),
                      child: const Icon(LucideIcons.plus, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: C.blue, borderRadius: BorderRadius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -46,
                  top: -46,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Invite friends, play more', style: d(18, c: Colors.white)),
                    const SizedBox(height: 4),
                    Text('You both get ₹$reward off when they book their first game.', style: t(13, c: C.blueSoft)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              code,
                              style: t(14, w: FontWeight.w700, c: Colors.white, ls: 1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GhostButton(
                          copied ? 'Copied' : 'Copy',
                          height: 44,
                          radius: 12,
                          fontSize: 13,
                          fg: C.blue,
                          border: Colors.transparent,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: code));
                            setState(() => copied = true);
                          },
                        ),
                        const SizedBox(width: 8),
                        GhostButton(
                          'Share',
                          height: 44,
                          radius: 12,
                          fontSize: 13,
                          bg: C.lime,
                          border: Colors.transparent,
                          onTap: () {
                            SharePlus.instance.share(
                              ShareParams(text: 'Join me on Turflet! Use my code $code and we both get ₹$reward off.'),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Segmented(
              labels: const ['Groups', 'Friends', 'Requests'],
              badges: [0, 0, requests.length],
              index: tab,
              onChanged: _cubit.selectTab,
            ),
          ),
          if (!loaded) const ListSkeleton(count: 3, leading: 60, padding: EdgeInsets.fromLTRB(20, 14, 20, 0)),
          if (loaded && tab == 0) _groups(st.groups),
          if (loaded && tab == 1) _friends(st.friends),
          if (loaded && tab == 2) _requests(st.requests, st.nearby),
        ],
      ),
    );
  }

  Widget _groups(List<Json> groups) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var gi = 0; gi < groups.length; gi++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  await context.pushGroup(groups[gi]['id']);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: shadowSoft, color: Colors.white),
                  child: Row(
                    children: [
                      Img(groups[gi]['image'], width: 60, height: 60, radius: BorderRadius.circular(16)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(groups[gi]['name'], style: d(16)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SportPill(asMap(groups[gi]['sport'])),
                                Text('${groups[gi]['member_count']} members', style: t(12, c: C.muted)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              groups[gi]['next'],
                              style: t(12, w: FontWeight.w600, c: groups[gi]['has_next'] == true ? C.green700 : C.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 30.0 + 22 * ((groups[gi]['avatars'] as List).length - 1).clamp(0, 2),
                        height: 30,
                        child: Stack(
                          children: [
                            for (var k = 0; k < (groups[gi]['avatars'] as List).length && k < 3; k++)
                              Positioned(
                                left: k * 22.0,
                                child: Avatar(groups[gi]['avatars'][k], index: gi + k, size: 30, ring: true),
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
        GestureDetector(
          onTap: _createGroup,
          child: DashedBorderBox(
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.plus, size: 18, color: C.brand),
                  const SizedBox(width: 8),
                  Text(
                    'Create a new group',
                    style: t(14, w: FontWeight.w700, c: C.brand),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _friends(List<Json> friends) => CardBox(
    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var k = 0; k < friends.length; k++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: k < friends.length - 1
                ? const BoxDecoration(
                    border: Border(bottom: BorderSide(color: C.divider)),
                  )
                : null,
            child: Row(
              children: [
                Avatar(friends[k]['initials'], index: k),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(friends[k]['name'], style: t(14, w: FontWeight.w700)),
                      Text(
                        friends[k]['meta'] ?? '',
                        style: t(12, c: C.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                GhostButton(
                  'Invite to game',
                  height: 36,
                  radius: 10,
                  fontSize: 12,
                  bg: C.mint,
                  fg: C.green700,
                  border: Colors.transparent,
                  onTap: () => context.pushCreate('match'),
                ),
              ],
            ),
          ),
        if (friends.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('No friends yet — add players near you.', style: t(14, c: C.muted)),
          ),
      ],
    ),
  );

  Widget _requests(List<Json> requests, List<Json> nearby) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requests.isNotEmpty) const Label('Friend requests', padding: EdgeInsets.only(bottom: 10)),
        for (var k = 0; k < requests.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              padding: const EdgeInsets.all(12),
              radius: 18,
              child: Row(
                children: [
                  Avatar(requests[k]['initials'], index: k + 3),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(requests[k]['name'], style: t(14, w: FontWeight.w700)),
                        Text(requests[k]['meta'], style: t(12, c: C.muted)),
                      ],
                    ),
                  ),
                  SquareIconButton(
                    LucideIcons.x,
                    size: 36,
                    iconSize: 16,
                    label: 'Decline',
                    onTap: () async {
                      await _cubit.declineRequest(requests[k]['request_id']);
                    },
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    'Accept',
                    height: 36,
                    radius: 10,
                    fontSize: 12,
                    bg: C.brand,
                    fg: Colors.white,
                    border: Colors.transparent,
                    onTap: () async {
                      await _cubit.acceptRequest(requests[k]['request_id']);
                    },
                  ),
                ],
              ),
            ),
          ),
        if (requests.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(16)),
            child: Text(
              'All caught up — no pending requests',
              textAlign: TextAlign.center,
              style: t(13, w: FontWeight.w600, c: C.green700),
            ),
          ),
        const Label('Players near you', padding: EdgeInsets.only(top: 20, bottom: 10)),
        for (var k = 0; k < nearby.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              padding: const EdgeInsets.all(12),
              radius: 18,
              child: Row(
                children: [
                  Avatar(nearby[k]['initials'], index: k + 1),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nearby[k]['name'], style: t(14, w: FontWeight.w700)),
                        const SizedBox(height: 3),
                        nearby[k]['sport'] != null
                            ? SportPill(asMap(nearby[k]['sport']), label: '${nearby[k]['sport']['name']} · ${nearby[k]['level']}')
                            : Text(nearby[k]['level'] ?? '', style: t(12, c: C.muted)),
                      ],
                    ),
                  ),
                  GhostButton(
                    nearby[k]['requested'] == true ? 'Requested' : 'Add friend',
                    height: 36,
                    radius: 10,
                    fontSize: 12,
                    bg: nearby[k]['requested'] == true ? C.ground : Colors.white,
                    fg: nearby[k]['requested'] == true ? C.muted : C.brand,
                    border: nearby[k]['requested'] == true ? C.line : C.brand,
                    onTap: () async {
                      await _cubit.addFriend(k);
                    },
                  ),
                ],
              ),
            ),
          ),
        if (nearby.isEmpty) Text('Nobody nearby yet.', style: t(13, c: C.muted)),
      ],
    ),
  );
}
