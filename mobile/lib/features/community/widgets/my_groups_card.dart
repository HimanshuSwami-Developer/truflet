import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/community_repository.dart';
import '../cubit/groups_cubit.dart';
import 'play_mode_sheet.dart';

/// Profile › My groups: groups I created or joined, with create and join-by-code.
class MyGroupsCard extends StatelessWidget {
  const MyGroupsCard({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => GroupsCubit(repository: c.read<CommunityRepository>())..load(),
    child: const _MyGroupsCard(),
  );
}

class _MyGroupsCard extends StatelessWidget {
  const _MyGroupsCard();

  Future<void> _open(BuildContext context, Json g) async {
    await context.pushGroup(g['id']);
    if (context.mounted) context.read<GroupsCubit>().load();
  }

  /// Asks for a group name or an invite code. Resolves to the text, or null.
  Future<String?> _ask(
    BuildContext context, {
    required String title,
    required String hint,
    required String action,
    bool code = false,
  }) {
    final ctl = TextEditingController();
    return sheet<String>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: d(22)),
          const SizedBox(height: 14),
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
              textCapitalization: code ? TextCapitalization.characters : TextCapitalization.words,
              style: code ? d(18, ls: 3) : t(15),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: t(15, c: C.muted),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(action, height: 52, onTap: () => Navigator.pop(ctx, ctl.text.trim())),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<GroupsCubit>();
    final name = await _ask(context, title: 'New group', hint: 'e.g. Weekend Ballers', action: 'Create group');
    if (name == null || name.length < 2 || !context.mounted) return;
    try {
      final g = await cubit.create(name);
      if (context.mounted) await _open(context, g);
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  Future<void> _join(BuildContext context) async {
    final cubit = context.read<GroupsCubit>();
    final code = await _ask(context, title: 'Join a group', hint: 'Invite code, e.g. 7KQ2XA', action: 'Join', code: true);
    if (code == null || code.isEmpty || !context.mounted) return;
    try {
      final g = await cubit.join(code);
      if (context.mounted) toast(context, 'You joined ${g['name']}');
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => CardBox(
    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: H2('My groups', size: 16)),
            Text('Play with friends', style: t(12, c: C.muted)),
          ],
        ),
        const SizedBox(height: 12),
        DataBuilder<GroupsCubit, List<Json>>(
          skeleton: const ListSkeleton(count: 2, padding: EdgeInsets.zero),
          builder: (context, groups) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Create a group for the people you play with — book once and everyone gets invited.',
                    style: t(13, c: C.muted, h: 1.4),
                  ),
                ),
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GroupRow(group: g, onTap: () => _open(context, g)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                'Create group',
                icon: LucideIcons.plus,
                height: 44,
                radius: 12,
                fontSize: 13,
                onTap: () => _create(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GhostButton(
                'Join with code',
                icon: LucideIcons.keyRound,
                height: 44,
                radius: 12,
                fontSize: 13,
                onTap: () => _join(context),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
