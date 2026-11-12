import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/community_repository.dart';
import '../../auth/auth_guard.dart';
import '../cubit/groups_cubit.dart';

/// "Book a slot" on a venue: play solo with strangers, or with one of my groups.
Future<void> choosePlayMode(BuildContext context, {required Json venue, int? sportId}) async {
  final choice = await sheet<String>(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How do you want to play?', style: d(22)),
        const SizedBox(height: 6),
        Text(venue['name'] ?? '', style: t(14, c: C.muted)),
        const SizedBox(height: 16),
        _ModeTile(
          icon: LucideIcons.userPlus,
          bg: C.limeSoft,
          fg: C.green700,
          title: 'Play solo with strangers',
          subtitle: 'Join an open game here, or start one others can join and split the cost.',
          onTap: () => Navigator.pop(ctx, 'solo'),
        ),
        const SizedBox(height: 10),
        _ModeTile(
          icon: LucideIcons.users,
          bg: C.blueSoft,
          fg: C.blue,
          title: 'Play with a group',
          subtitle: 'Pick one of your groups or create a new one. Members get invited once you book.',
          onTap: () => Navigator.pop(ctx, 'group'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'solo') {
    await context.pushOpenGames(OpenGamesArgs(venue: venue, sportId: sportId));
    return;
  }
  if (!await requireLogin(context) || !context.mounted) return;
  final group = await pickGroup(context);
  if (group == null || !context.mounted) return;
  await context.pushSlotBooking(SlotBookingArgs(venue: venue, initialSportId: sportId, group: group));
}

/// Lists my groups plus "Create a new group". Resolves to the chosen group, or null.
Future<Json?> pickGroup(BuildContext context) => sheet<Json>(
  context,
  (ctx) => BlocProvider(
    create: (c) => GroupsCubit(repository: c.read<CommunityRepository>())..load(),
    child: const _GroupPicker(),
  ),
);

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ModeTile({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: C.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 22, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t(15, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t(12, c: C.muted, h: 1.4)),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: C.muted),
          ],
        ),
      ),
    ),
  );
}

class _GroupPicker extends StatefulWidget {
  const _GroupPicker();
  @override
  State<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<_GroupPicker> {
  final name = TextEditingController();
  bool creating = false, busy = false;

  Future<void> _create() async {
    if (name.text.trim().length < 2) return;
    setState(() => busy = true);
    try {
      final g = await context.read<GroupsCubit>().create(name.text);
      if (mounted) Navigator.pop(context, g);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Play with a group', style: d(22)),
      const SizedBox(height: 6),
      Text('Everyone in the group gets a notification once the slot is booked.', style: t(13, c: C.muted, h: 1.4)),
      const SizedBox(height: 14),
      DataBuilder<GroupsCubit, List<Json>>(
        skeleton: const ListSkeleton(count: 2, padding: EdgeInsets.zero),
        builder: (context, groups) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (groups.isNotEmpty) const Label('Your groups', padding: EdgeInsets.only(bottom: 8)),
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GroupRow(group: g, onTap: () => Navigator.pop(context, g)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      if (!creating)
        GhostButton('Create a new group', icon: LucideIcons.plus, onTap: () => setState(() => creating = true))
      else ...[
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: C.ground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.line),
          ),
          child: TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: t(15),
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Group name, e.g. Weekend Ballers',
              hintStyle: t(15, c: C.muted),
            ),
          ),
        ),
        const SizedBox(height: 10),
        PrimaryButton('Create & continue', height: 52, loading: busy, onTap: _create),
      ],
    ],
  );
}

/// One group in a list: initials, name, member count.
class GroupRow extends StatelessWidget {
  final Json group;
  final VoidCallback onTap;
  const GroupRow({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initials = (group['initials'] as List? ?? const []).cast<String>();
    final n = group['member_count'] ?? 0;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 30.0 + 18 * (initials.length - 1).clamp(0, 2),
                height: 30,
                child: Stack(
                  children: [
                    for (var k = 0; k < initials.length && k < 3; k++)
                      Positioned(
                        left: k * 18.0,
                        child: Avatar(initials[k], index: k, size: 30, ring: true),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group['name'] ?? '', style: t(15, w: FontWeight.w700)),
                    Text('$n member${n == 1 ? '' : 's'}', style: t(12, c: C.muted)),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18, color: C.muted),
            ],
          ),
        ),
      ),
    );
  }
}
