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
import '../cubit/squad_builder_cubit.dart';

/// 4 · Squad Builder (Group view): capacity, friends with Known / Guest tags, one-time payment rule,
/// Open to solo players, and Book & Recover vs Crowdfund.
class SquadBuilderScreen extends StatelessWidget {
  final SquadArgs args;
  const SquadBuilderScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => SquadBuilderCubit(
      args: args,
      repository: c.read<LobbyRepository>(),
      splitFee: (c.read<AppCubit>().state.config['split_fee'] as int?) ?? 0,
    )..loadRecent(),
    child: const _SquadBuilderView(),
  );
}

class _SquadBuilderView extends StatelessWidget {
  const _SquadBuilderView();

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<SquadBuilderCubit>();
    try {
      final lobby = await cubit.create();
      if (!context.mounted) return;
      // Creating a match never charges anything: the host locks the turf (or pays a pool share)
      // from the Match Room when ready, and friends get an invite to accept.
      toast(
        context,
        lobby['status'] == 'draft' ? 'Match created. Lock the turf when you\'re ready.' : 'Match created. Pay your share to start the pool.',
      );
      await context.replaceWithMatch(lobby['id']);
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SquadBuilderCubit, SquadBuilderState>(
    builder: (context, st) {
      final cubit = context.read<SquadBuilderCubit>();
      final top = MediaQuery.of(context).padding.top;
      final a = st.args;
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
                        Text('Build your squad', style: d(20)),
                        Text(
                          '${a.venue['name']} · ${st.dateLabel} · ${fmtHour(a.startHour)} – ${fmtHour(a.startHour + a.duration)}',
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _slotCard(st),
                  const Label(
                    'Team capacity',
                    padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
                  ),
                  _capacity(st, cubit),
                  const Label(
                    'Your squad',
                    padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
                  ),
                  _squad(context, st, cubit),
                  const Label(
                    'Payment rule · set once',
                    padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _option(
                          st.rule == 'split',
                          'Split equally',
                          st.split
                              ? '${inr(st.perHead)} each'
                              : 'Everyone pays a share',
                          LucideIcons.arrowLeftRight,
                          () => cubit.setRule('split'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _option(
                          st.rule == 'host',
                          'I\'ll pay full',
                          'Everyone else plays free',
                          LucideIcons.handCoins,
                          () => cubit.setRule('host'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _publicToggle(st, cubit),
                  if (st.split) ...[
                    const Label(
                      'How to book the turf',
                      padding: EdgeInsets.fromLTRB(0, 20, 0, 10),
                    ),
                    _modeCard(
                      st,
                      'book_recover',
                      'Book & recover',
                      'Pay ${inr(a.turfPrice)} now to lock the turf. Shares come back to you through escrow as '
                          'players pay — released when your group checks in.',
                      LucideIcons.lock,
                      st.isPrime ? 'Recommended for prime slots' : null,
                      cubit,
                    ),
                    const SizedBox(height: 10),
                    _modeCard(
                      st,
                      'crowdfund',
                      'Crowdfund first',
                      'Pay only your share. The turf is booked once the pool covers it — if another group books '
                          'first or it isn\'t full near kickoff, you choose what to do and paid players are refunded.',
                      LucideIcons.piggyBank,
                      st.isPrime ? 'Risky at peak hours' : 'Zero upfront risk',
                      cubit,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _summary(st),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                14 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: C.line)),
              ),
              child: PrimaryButton(
                st.crowdfund
                    ? 'Create lobby · pay ${inr(st.hostPaysNow)}'
                    : st.isPublic && st.openSpots > 0
                    ? 'Lock turf & publish lobby'
                    : 'Lock turf · ${inr(a.turfPrice)}',
                loading: st.busy,
                trailing: const Icon(
                  LucideIcons.arrowRight,
                  color: Colors.white,
                  size: 18,
                ),
                onTap: () => _create(context),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _slotCard(SquadBuilderState st) {
    final a = st.args;
    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Img(
            a.venue['image'],
            width: 52,
            height: 52,
            radius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a.sport['name']} · ${a.court['name']}',
                  style: t(15, w: FontWeight.w700),
                ),
                Text(
                  '${st.dateLabel} · ${fmtTime(a.startHour)} – ${fmtTime(a.startHour + a.duration)}',
                  style: t(13, c: C.muted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(inr(a.turfPrice), style: d(18)),
              Text('turf', style: t(11, c: C.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _capacity(SquadBuilderState st, SquadBuilderCubit cubit) {
    Widget btn(
      String label,
      bool primary,
      VoidCallback onTap,
      String semantics,
    ) => Semantics(
      button: true,
      label: semantics,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? C.brand : C.ground,
            borderRadius: BorderRadius.circular(12),
            border: primary ? null : Border.all(color: C.line),
          ),
          child: Text(
            label,
            style: t(20, w: FontWeight.w700, c: primary ? Colors.white : C.ink),
          ),
        ),
      ),
    );
    final half = st.capacity ~/ 2;
    return CardBox(
      padding: const EdgeInsets.all(14),
      shadow: null,
      border: Border.all(color: C.line),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total players', style: t(14, w: FontWeight.w600)),
                Text(
                  '${st.capacity.isEven ? '${half}v$half · ' : ''}including you · max ${st.maxPlayers}',
                  style: t(12, c: C.muted),
                ),
              ],
            ),
          ),
          btn(
            '−',
            false,
            () => cubit.setCapacity(st.capacity - 1),
            'Fewer players',
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${st.capacity}',
              textAlign: TextAlign.center,
              style: d(22),
            ),
          ),
          btn(
            '+',
            true,
            () => cubit.setCapacity(st.capacity + 1),
            'More players',
          ),
        ],
      ),
    );
  }

  Widget _squad(
    BuildContext context,
    SquadBuilderState st,
    SquadBuilderCubit cubit,
  ) {
    final me = context.read<AppCubit>().state.user ?? const {};
    final recent = st.recent
        .where((p) => !st.friends.any((f) => f['user_id'] == p['id']))
        .toList();
    return CardBox(
      padding: const EdgeInsets.all(14),
      shadow: null,
      border: Border.all(color: C.line),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _personRow(
            me['initials'] ?? 'ME',
            'You',
            'Host',
            C.mint,
            C.green700,
            null,
          ),
          for (final (i, f) in st.friends.indexed)
            _personRow(
              f['initials'] ?? '',
              f['name'] ?? '',
              f['tag'] == 'guest' ? 'Guest' : 'Known',
              f['tag'] == 'guest' ? C.amberSoft : C.blueSoft,
              f['tag'] == 'guest' ? C.amber : C.blue,
              () => cubit.remove(i),
              index: i + 1,
            ),
          if (st.openSpots > 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.ground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.userPlus, size: 16, color: C.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      st.isPublic
                          ? '${st.openSpots} open spot${st.openSpots == 1 ? '' : 's'} for solo players'
                          : '${st.openSpots} more of your guests (you cover them)',
                      style: t(13, c: C.mutedInk),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  'Add friend',
                  icon: LucideIcons.userPlus,
                  height: 44,
                  radius: 12,
                  fontSize: 13,
                  onTap: () => _addFriend(context, cubit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GhostButton(
                  'Add guest',
                  icon: LucideIcons.user,
                  height: 44,
                  radius: 12,
                  fontSize: 13,
                  onTap: () => _addGuest(context, cubit),
                ),
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Played with recently', style: t(12, c: C.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in recent.take(8))
                  GestureDetector(
                    onTap: () {
                      final err = cubit.addKnown(p);
                      if (err != null) toast(context, err);
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: C.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Avatar(
                            p['initials'] ?? '',
                            size: 22,
                            index: (p['id'] ?? 0) as int,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            (p['name'] ?? '').toString().split(' ').first,
                            style: t(12, w: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.plus,
                            size: 12,
                            color: C.brand,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _personRow(
    String initials,
    String name,
    String tag,
    Color bg,
    Color fg,
    VoidCallback? onRemove, {
    int index = 0,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Avatar(initials, size: 32, index: index),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: t(14, w: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Pill(tag, bg: bg, fg: fg),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            icon: const Icon(LucideIcons.x, size: 16, color: C.muted),
          ),
      ],
    ),
  );

  Future<void> _addFriend(BuildContext context, SquadBuilderCubit cubit) async {
    var busy = false;
    String? error;
    final player = await sheet<Json>(
      context,
      (ctx) => _OwnedController(
        builder: (contact) => StatefulBuilder(
          builder: (ctx, set) {
            Future<void> find() async {
              set(() => busy = true);
              try {
                final p = await cubit.lookup(contact.text);
                if (ctx.mounted) Navigator.pop(ctx, p);
              } catch (e) {
                set(() {
                  busy = false;
                  error = e.toString();
                });
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add a friend', style: d(22)),
                const SizedBox(height: 6),
                Text(
                  'Known players are on Turflet: they get an invite and join once they accept.',
                  style: t(13, c: C.muted, h: 1.4),
                ),
                const SizedBox(height: 14),
                _field(
                  contact,
                  'Email, mobile or referral code',
                  TextInputType.emailAddress,
                  autofocus: true,
                  onSubmit: find,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: t(13, c: C.redInk)),
                  ),
                const SizedBox(height: 12),
                PrimaryButton(
                  'Find player',
                  height: 52,
                  loading: busy,
                  onTap: find,
                ),
              ],
            );
          },
        ),
      ),
    );
    if (player == null || !context.mounted) return;
    final err = cubit.addKnown(player);
    if (err != null) toast(context, err);
  }

  Future<void> _addGuest(BuildContext context, SquadBuilderCubit cubit) async {
    final value = await sheet<String>(
      context,
      (ctx) => _OwnedController(
        builder: (name) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a guest', style: d(22)),
            const SizedBox(height: 6),
            Text(
              'Guests aren\'t on Turflet. You cover their share.',
              style: t(13, c: C.muted, h: 1.4),
            ),
            const SizedBox(height: 14),
            _field(
              name,
              'Guest name',
              TextInputType.name,
              autofocus: true,
              onSubmit: () => Navigator.pop(ctx, name.text),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              'Add guest',
              height: 52,
              onTap: () => Navigator.pop(ctx, name.text),
            ),
          ],
        ),
      ),
    );
    if (value == null || !context.mounted) return;
    final err = cubit.addGuest(value);
    if (err != null) toast(context, err);
  }

  Widget _field(
    TextEditingController c,
    String hint,
    TextInputType type, {
    bool autofocus = false,
    VoidCallback? onSubmit,
  }) => Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: C.ground,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.line),
    ),
    child: TextField(
      controller: c,
      autofocus: autofocus,
      keyboardType: type,
      textCapitalization: type == TextInputType.name
          ? TextCapitalization.words
          : TextCapitalization.none,
      style: t(15),
      onSubmitted: (_) => onSubmit?.call(),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: hint,
        hintStyle: t(15, c: C.muted),
      ),
    ),
  );

  Widget _option(
    bool on,
    String title,
    String sub,
    IconData icon,
    VoidCallback onTap,
  ) => Choice(
    selected: on,
    filled: false,
    selBg: C.mint,
    selWidth: 2,
    height: 96,
    onTap: onTap,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: on ? C.green700 : C.muted),
            const Spacer(),
            RadioDot(on),
          ],
        ),
        const SizedBox(height: 6),
        Text(title, style: t(14, w: FontWeight.w700)),
        Text(
          sub,
          style: t(11, c: C.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  Widget _publicToggle(SquadBuilderState st, SquadBuilderCubit cubit) {
    final can = st.openSpots > 0;
    final on = st.isPublic && can;
    return Semantics(
      toggled: on,
      button: true,
      child: GestureDetector(
        onTap: can ? () => cubit.setPublic(!st.isPublic) : null,
        child: CardBox(
          padding: const EdgeInsets.all(14),
          shadow: null,
          border: Border.all(color: on ? C.brand : C.line),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open to solo players',
                      style: t(14, w: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !can
                          ? 'Your squad is full — this is a private booking.'
                          : on
                          ? 'List ${st.openSpots} spot${st.openSpots == 1 ? '' : 's'} publicly. You screen every request '
                                'in a private chat first.'
                          : 'Private: only your squad plays.',
                      style: t(12, c: C.muted, h: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Toggle(on),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(
    SquadBuilderState st,
    String id,
    String title,
    String body,
    IconData icon,
    String? badge,
    SquadBuilderCubit cubit,
  ) {
    final on = st.mode == id;
    return GestureDetector(
      onTap: () => cubit.setMode(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? C.mint : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? C.brand : C.line, width: on ? 2 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: on ? C.green700 : C.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title, style: t(14, w: FontWeight.w700)),
                      if (badge != null)
                        Pill(
                          badge,
                          bg: badge.startsWith('Risky') ? C.orangeSoft : C.lime,
                          fg: badge.startsWith('Risky') ? C.orangeInk : C.ink,
                          size: 10,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: t(12, c: C.mutedInk, h: 1.45)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RadioDot(on),
          ],
        ),
      ),
    );
  }

  Widget _summary(SquadBuilderState st) {
    final a = st.args;
    final others = st.capacity - 1 - st.guests;
    return CardBox(
      color: C.ground,
      shadow: null,
      border: Border.all(color: C.line),
      child: Column(
        children: [
          PriceRow(
            'Turf · ${a.duration} hr${a.duration == 1 ? '' : 's'}',
            inr(a.turfPrice),
          ),
          const SizedBox(height: 8),
          PriceRow(
            'Players',
            '${st.capacity} (${st.squad} in squad${st.isPublic && st.openSpots > 0 ? ', ${st.openSpots} open' : ''})',
          ),
          if (st.split) ...[
            const SizedBox(height: 8),
            PriceRow(
              'Each player pays',
              '${inr(st.share)} + ${inr(st.splitFee)} fee',
            ),
            if (st.guests > 0) ...[
              const SizedBox(height: 8),
              PriceRow(
                'You cover ${st.guests} guest${st.guests == 1 ? '' : 's'}',
                inr(st.share * st.guests),
              ),
            ],
          ],
          const SizedBox(height: 12),
          PriceRow(
            st.crowdfund
                ? 'You pay now (into escrow)'
                : 'You pay now (+ booking fee)',
            inr(st.hostPaysNow),
            bold: true,
            top: true,
          ),
          if (st.split && !st.crowdfund && others > 0) ...[
            const SizedBox(height: 6),
            PriceRow(
              'You recover up to',
              inr(st.share * others),
              color: C.green700,
            ),
          ],
        ],
      ),
    );
  }
}

/// Owns a [TextEditingController] for a bottom sheet's lifetime. Disposing it right after
/// `await sheet(...)` is too early: the sheet's exit animation still rebuilds the TextField.
class _OwnedController extends StatefulWidget {
  final Widget Function(TextEditingController controller) builder;
  const _OwnedController({required this.builder});

  @override
  State<_OwnedController> createState() => _OwnedControllerState();
}

class _OwnedControllerState extends State<_OwnedController> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
