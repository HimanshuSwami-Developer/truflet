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
import '../../../data/repositories/user_repository.dart';
import '../../auth/view/profile_form.dart';
import '../cubit/profile_cubit.dart';

/// 19 · My profile
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => ProfileCubit(users: c.read<UserRepository>(), app: c.read<AppCubit>()),
    // refresh the profile whenever the player switches to this tab
    child: BlocListener<AppCubit, AppState>(
      listenWhen: (prev, cur) => cur.tab == 4 && prev.tab != 4,
      listener: (context, _) => context.read<AppCubit>().refreshMe(),
      child: const _ProfileView(),
    ),
  );
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();
  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

const _levels = [
  ('Beginner', 0.3, C.teal, C.tealSoft),
  ('Intermediate', 0.6, C.amber, C.amberSoft),
  ('Advanced', 0.9, C.green700, C.mint),
];

/// "Editing" (level buttons visible) is view-only state.
class _ProfileViewState extends State<_ProfileView> {
  bool editing = false;

  Future<void> _setSports(List<Json> sports) async {
    final error = await context.read<ProfileCubit>().setSports(sports);
    if (error != null && mounted) toast(context, error);
  }

  Future<void> _editDetails() async {
    await sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit details', style: d(22)),
          const SizedBox(height: 16),
          ProfileForm(
            submitLabel: 'Save details',
            showHandle: true,
            onSaved: () {
              Navigator.pop(ctx);
              toast(context, 'Profile updated');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addSport(Json u) async {
    final s = context.read<AppCubit>().state;
    final have = asList(u['sports']).map((x) => x['sport_id']).toSet();
    final options = s.sports.where((x) => !have.contains(x['id'])).toList();
    if (options.isEmpty) return;
    final picked = await sheet<Json>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a sport', style: d(22)),
          const SizedBox(height: 14),
          for (final o in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Img(o['image'], width: 40, height: 40, radius: BorderRadius.circular(12)),
              title: Text(o['name'], style: t(15, w: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, o),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _setSports([
      ...asList(u['sports']),
      {'sport_id': picked['id'], 'level': 0},
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppCubit>();
    final s = app.state;
    final u = s.user;
    if (u == null) return const ProfileSkeleton();
    final top = MediaQuery.of(context).padding.top;
    final stats = asMap(u['stats']);
    final sports = asList(u['sports']);
    final area = u['home_area'] == null ? s.areaName : u['home_area']['name'];
    return RefreshIndicator(
      color: C.brand,
      onRefresh: app.refreshMe,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, top + 16, 20, 70),
            decoration: const BoxDecoration(
              color: C.brand,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -80,
                  top: -56 - top,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(color: C.lime.withValues(alpha: 0.18), shape: BoxShape.circle),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('My profile', style: d(22, c: Colors.white)),
                    ),
                    GhostButton(
                      editing ? 'Done' : 'Edit profile',
                      height: 40,
                      radius: 12,
                      fontSize: 13,
                      fg: Colors.white,
                      bg: Colors.white.withValues(alpha: 0.18),
                      border: Colors.transparent,
                      onTap: () => setState(() => editing = !editing),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -56),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: shadowBig),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _editDetails,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 76,
                              height: 76,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: C.lime, borderRadius: BorderRadius.circular(24)),
                                    child: Text(u['initials'] ?? 'ME', style: d(26)),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: C.brand,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                      child: Icon(
                                        editing ? LucideIcons.pencil : LucideIcons.check,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((u['name'] ?? '').toString().isEmpty ? 'Add your name' : u['name'], style: d(20)),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${(u['handle'] ?? '').toString().isEmpty ? '' : '@${u['handle']} · '}$area',
                                    style: t(13, c: C.muted),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${u['email']} · verified',
                                    style: t(12, c: C.muted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.only(top: 12),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: C.divider)),
                        ),
                        child: Row(
                          children: [
                            _stat('${stats['games'] ?? 0}', 'Games'),
                            _stat('${stats['hours'] ?? 0}h', 'Played'),
                            _stat('${stats['win_rate'] ?? 0}%', 'Win rate', C.green700),
                            _stat('${stats['titles'] ?? 0}', 'Titles', C.amber),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                CardBox(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: H2('Personal details', size: 16)),
                          GestureDetector(
                            onTap: _editDetails,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'Edit',
                                style: t(13, w: FontWeight.w700, c: C.brand),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _detail(LucideIcons.user, 'Name', u['name'], 'Add your name'),
                      _detail(LucideIcons.mail, 'Email', u['email'], '', verified: true),
                      _detail(LucideIcons.phone, 'Mobile', u['phone'], 'Add mobile number'),
                      _detail(LucideIcons.mapPin, 'Address', u['address'], 'Add address (optional)', last: true),
                    ],
                  ),
                ),
                CardBox(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: H2('My sports', size: 16)),
                          Text(editing ? 'Tap Change to set level' : 'Shown to teammates', style: t(12, c: C.muted)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < sports.length; i++) _sportRow(sports, i),
                      if (sports.isEmpty) Text('Add the sports you play so teammates can find you.', style: t(13, c: C.muted)),
                      if (editing && sports.length < s.sports.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GhostButton(
                            'Add sport',
                            icon: LucideIcons.plus,
                            height: 40,
                            radius: 12,
                            fontSize: 13,
                            onTap: () => _addSport(u),
                          ),
                        ),
                    ],
                  ),
                ),
                CardBox(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    children: [
                      _switch(
                        'Show me to nearby players',
                        'Lets others find you in Squad › Players near you',
                        u['show_to_nearby'] == true,
                        () => app.updateMe({'show_to_nearby': !(u['show_to_nearby'] == true)}),
                        false,
                      ),
                      _switch(
                        'Game & slot notifications',
                        'RSVPs, invites, tournament updates',
                        u['notifications_on'] == true,
                        () => app.updateMe({'notifications_on': !(u['notifications_on'] == true)}),
                        true,
                      ),
                    ],
                  ),
                ),
                CardBox(
                  margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _menu(
                        Icons.favorite_border,
                        C.rose,
                        C.roseSoft,
                        'Saved venues',
                        '${s.saved.length} venues',
                        () => context.pushSaved(),
                      ),
                      _menu(LucideIcons.trophy, C.amber, C.amberSoft, 'My tournaments', 'Hosting & played', () => app.setTab(2)),
                      _menu(
                        LucideIcons.creditCard,
                        C.blue,
                        C.blueSoft,
                        'Payments & refunds',
                        'Wallet ${inr(u['wallet_balance'])}',
                        () => app.setTab(1),
                      ),
                      _menu(
                        LucideIcons.userPlus,
                        C.purple,
                        C.purpleSoft,
                        'Invite friends',
                        'Code ${u['referral_code']} · ₹${s.config['referral_reward'] ?? 50} each',
                        () => app.setTab(3),
                      ),
                      _menu(
                        LucideIcons.circleHelp,
                        C.green700,
                        C.mint,
                        'Help & support',
                        'Chat, call, FAQs',
                        () => context.pushHelp(),
                      ),
                      _menu(
                        LucideIcons.shield,
                        C.teal,
                        C.tealSoft,
                        'Privacy & refund policy',
                        'How we handle data & money',
                        () => context.pushPolicy(),
                        last: true,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: GhostButton(
                    'Log out',
                    fg: const Color(0xFFB91C1C),
                    border: const Color(0xFFFECACA),
                    onTap: () async {
                      await app.logout();
                      app.setTab(0);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Turflet v${s.config['app_version'] ?? '1.1'}', style: t(12, c: C.muted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, dynamic value, String placeholder, {bool verified = false, bool last = false}) {
    final empty = (value ?? '').toString().trim().isEmpty;
    return InkWell(
      onTap: verified ? null : _editDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: last
            ? null
            : const BoxDecoration(
                border: Border(bottom: BorderSide(color: C.divider)),
              ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: C.green700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t(11, c: C.muted)),
                  const SizedBox(height: 1),
                  Text(
                    empty ? placeholder : value.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: empty ? t(14, w: FontWeight.w600, c: C.brand) : t(14, w: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (verified) ...[
              const Icon(LucideIcons.badgeCheck, size: 16, color: C.green700),
              const SizedBox(width: 4),
              Text(
                'Verified',
                style: t(12, w: FontWeight.w600, c: C.green700),
              ),
            ] else
              const Icon(LucideIcons.chevronRight, size: 18, color: C.muted),
          ],
        ),
      ),
    );
  }

  Widget _stat(String v, String l, [Color? c]) => Expanded(
    child: Column(
      children: [
        Text(v, style: d(20, c: c ?? C.ink)),
        Text(l, style: t(11, c: C.muted)),
      ],
    ),
  );

  Widget _sportRow(List<Json> sports, int i) {
    final sp = sports[i];
    final lv = _levels[(sp['level'] as int).clamp(0, 2)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Img(sp['image'], width: 40, height: 40, radius: BorderRadius.circular(12)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(sp['name'], style: t(14, w: FontWeight.w700)),
                    ),
                    Pill(lv.$1, bg: lv.$4, fg: lv.$3, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: lv.$2),
                    duration: const Duration(milliseconds: 250),
                    builder: (_, v, _) =>
                        LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: C.divider, color: lv.$3),
                  ),
                ),
              ],
            ),
          ),
          if (editing) ...[
            const SizedBox(width: 12),
            GhostButton(
              'Change',
              height: 34,
              radius: 10,
              fontSize: 12,
              bg: C.ground,
              onTap: () {
                final next = [...sports.map((x) => Map<String, dynamic>.from(x))];
                next[i]['level'] = ((sp['level'] as int) + 1) % 3;
                _setSports(next);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _switch(String title, String sub, bool on, VoidCallback onTap, bool border) => Semantics(
    toggled: on,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: border
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: C.divider)),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(14, w: FontWeight.w600)),
                  Text(sub, style: t(12, c: C.muted)),
                ],
              ),
            ),
            Toggle(on),
          ],
        ),
      ),
    ),
  );

  Widget _menu(IconData icon, Color fg, Color bg, String label, String sub, VoidCallback onTap, {bool last = false}) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: C.divider)),
            ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: t(14, w: FontWeight.w600)),
                Text(sub, style: t(12, c: C.muted)),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, size: 18, color: C.muted),
        ],
      ),
    ),
  );
}
