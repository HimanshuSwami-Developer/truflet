import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/router/app_navigation.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/lobby_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import '../cubit/match_room_cubit.dart';
import '../widgets/chat.dart';
import '../widgets/lobby_widgets.dart';
import '../widgets/split_checkout_sheet.dart';
import 'lobbies_screen.dart';

/// 5 + 6 · Match Room: pinned header (Turf Locked / Unbooked, Paid 8/10, Booking QR / PIN), in-chat
/// 15-minute UPI payment cards, group chat, players, and the host's Requests tab for screening.
class MatchRoomScreen extends StatelessWidget {
  final int lobbyId;
  const MatchRoomScreen({super.key, required this.lobbyId});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => MatchRoomCubit(lobbyId: lobbyId, repository: c.read<LobbyRepository>())..load(),
    child: const _MatchRoomView(),
  );
}

class _MatchRoomView extends StatefulWidget {
  const _MatchRoomView();
  @override
  State<_MatchRoomView> createState() => _MatchRoomViewState();
}

class _MatchRoomViewState extends State<_MatchRoomView> {
  int tab = 0;
  final scroll = ScrollController();

  MatchRoomCubit get _cubit => context.read<MatchRoomCubit>();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ actions

  Future<void> _run(String action, [Json body = const {}]) async {
    try {
      final msg = await _cubit.action(action, body);
      if (mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<bool> _confirm(String title, String body, String cta, {Color color = C.orange}) async {
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: d(22)),
          const SizedBox(height: 8),
          Text(body, style: t(14, c: C.muted, h: 1.5)),
          const SizedBox(height: 16),
          PrimaryButton(cta, height: 52, color: color, shadow: false, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _pay() async {
    final lobby = await showSplitCheckout(context, lobbyId: _cubit.lobbyId);
    if (lobby != null && mounted) {
      await _cubit.applied(lobby);
      if (mounted) toast(context, lobby['status'] == 'locked' ? 'Paid — the turf is locked!' : 'Paid into escrow ✓');
    }
  }

  Future<void> _payBalance(int amount) async {
    final lobby = await showPayBalance(context, lobbyId: _cubit.lobbyId, amount: amount);
    if (lobby != null && mounted) {
      await _cubit.applied(lobby);
      if (mounted) toast(context, 'Balance paid — the turf is locked.');
    }
  }

  /// Book & Recover host is ready to pay: hold the slot, then pay for it.
  Future<void> _lockTurf() async {
    try {
      final r = await context.read<LobbyRepository>().action(_cubit.lobbyId, 'lock');
      await _cubit.applied(r);
      if (!mounted) return;
      await context.pushPayment(asMap(r['checkout_booking']));
      _cubit.reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  /// Host never finished paying the held slot: resume the payment.
  Future<void> _resumeHostPayment(int bookingId) async {
    try {
      final b = await context.read<BookingRepository>().details(bookingId);
      if (!mounted) return;
      await context.pushPayment(b);
      _cubit.reload();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _checkin() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Turn on location to check in — or show your booking QR at the counter.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await _run('checkin', {'lat': pos.latitude, 'lng': pos.longitude});
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  Future<void> _report() async {
    final reason = TextEditingController();
    final ok = await sheet<bool>(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report a no-show', style: d(22)),
          const SizedBox(height: 8),
          Text(
            'The host\'s payout stays in escrow while our support team reviews it. Use this only if the host or the '
            'turf didn\'t show up.',
            style: t(14, c: C.muted, h: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.ground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: TextField(
              controller: reason,
              minLines: 3,
              maxLines: 5,
              style: t(14),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'What happened?',
                hintStyle: t(14, c: C.muted),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton('Report no-show', height: 52, color: C.red, shadow: false, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok == true) await _run('report', {'reason': text});
  }

  Future<void> _leave(Json lobby) async {
    final mins = DateTime.parse(lobby['starts_at']).difference(DateTime.now()).inMinutes;
    final paid = (lobby['me']?['status']) == 'confirmed' && (lobby['per_head'] ?? 0) > 0;
    final body = !paid
        ? 'Your spot opens up for someone else.'
        : lobby['status'] == 'crowdfunding'
        ? 'The turf isn\'t booked yet, so your share is refunded right away.'
        : mins >= 30
        ? 'Your share is refunded once a replacement player joins (or the slot is released).'
        : 'Kickoff is less than 30 minutes away — your share is not refundable.';
    if (!await _confirm('Leave this match?', body, 'Leave match')) return;
    await _run('leave');
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _cancelMatch() async {
    if (!await _confirm(
      'Cancel the match?',
      'Everyone who paid a share is refunded in full. If the turf is booked, your own refund follows the venue\'s '
          'cancellation policy.',
      'Cancel match',
      color: C.red,
    )) {
      return;
    }
    await _run('cancel');
  }

  Future<void> _unpublish() async {
    if (!await _confirm(
      'Stop recruiting?',
      'Open spots are removed from the public list, pending requests are closed and solo players who paid are '
          'refunded. Your squad and chat stay as they are.',
      'Unpublish lobby',
    )) {
      return;
    }
    await _run('unpublish');
  }

  Future<void> _switchSlot(Json lobby) async {
    final pick = await sheet<Json>(context, (_) => _SwitchSlotSheet(lobby: lobby));
    if (pick != null) await _run('switch-slot', pick);
  }

  void _showPass(Json booking) => sheet(
    context,
    (ctx) => Column(
      children: [
        Text('Booking pass', style: d(22)),
        const SizedBox(height: 4),
        Text('Show the QR at the counter, or tell the manager the PIN', style: t(13, c: C.muted)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.line),
          ),
          child: QrImageView(data: booking['qr_payload'] ?? '', size: 200, eyeStyle: const QrEyeStyle(color: C.ink)),
        ),
        const SizedBox(height: 16),
        Text('CHECK-IN PIN', style: t(11, w: FontWeight.w600, c: C.muted, ls: 1.2)),
        const SizedBox(height: 4),
        Text(
          (booking['pin'] ?? '----').toString().split('').join(' '),
          style: d(36, ls: 4, c: C.brand),
        ),
        const SizedBox(height: 6),
        Text(booking['code'] ?? '', style: t(13, c: C.muted)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.limeSoft, borderRadius: BorderRadius.circular(14)),
          child: Text(
            'When the venue scans this, the match goes Live and the recovered shares are released to the host.',
            textAlign: TextAlign.center,
            style: t(12, c: C.green900, h: 1.4),
          ),
        ),
      ],
    ),
  );

  void _menu(Json lobby) {
    final host = asMap(lobby['host_actions']);
    final me = asMap(lobby['me']);
    final booking = lobby['booking'];
    Widget item(IconData icon, String label, VoidCallback onTap, {Color color = C.ink}) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: t(15, w: FontWeight.w600, c: color)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
    sheet(
      context,
      (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item(LucideIcons.mapPin, 'Venue details', () => context.pushVenue(lobby['venue']['id'])),
          if (booking != null) item(LucideIcons.ticket, 'Booking ticket', () => context.pushTicket(booking['id'])),
          if (host['can_switch'] == true) item(LucideIcons.calendarClock, 'Switch to another slot', () => _switchSlot(lobby)),
          if (host['can_unpublish'] == true) item(LucideIcons.eyeOff, 'Unpublish lobby', _unpublish),
          if (host['can_cancel'] == true) item(LucideIcons.x, 'Cancel match', _cancelMatch, color: C.redInk),
          if (me['can_leave'] == true) item(LucideIcons.logOut, 'Leave match', () => _leave(lobby), color: C.orangeInk),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) => BlocBuilder<MatchRoomCubit, MatchRoomState>(
    builder: (context, st) {
      final lobby = st.lobby;
      if (lobby == null) {
        return Scaffold(
          body: SafeArea(
            child: st.error != null
                ? Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(padding: EdgeInsets.all(20), child: BackSquare()),
                      ),
                      Expanded(child: ErrorRetry(st.error!, onRetry: _cubit.reload)),
                    ],
                  )
                : const ListSkeleton(count: 6),
          ),
        );
      }
      if (!st.inRoom) return _outside(lobby);
      final tabs = ['Chat', 'Players · ${lobby['taken']}', if (st.isHost) 'Requests'];
      final current = tab.clamp(0, tabs.length - 1);
      final live = ['draft', 'crowdfunding', 'locked'].contains(lobby['status']);
      return Scaffold(
        body: Column(
          children: [
            _header(lobby),
            _pinned(lobby),
            ..._banners(lobby, st),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Segmented(
                labels: tabs,
                index: current,
                height: 36,
                badges: [0, 0, if (st.isHost) (lobby['pending_requests'] ?? 0) as int],
                onChanged: (i) {
                  setState(() => tab = i);
                  if (i == 2) _cubit.loadRequests();
                },
              ),
            ),
            Expanded(
              child: switch (current) {
                0 => ChatList(
                  messages: st.messages,
                  controller: scroll,
                  onPay: asMap(lobby['me'])['can_pay'] == true ? _pay : null,
                ),
                1 => _players(lobby, st),
                _ => _requests(st),
              },
            ),
            if (current == 0 && live)
              Composer(
                onSend: (body) async {
                  final err = await _cubit.send(body);
                  if (err != null && mounted) toast(this.context, err);
                  return err == null;
                },
              ),
          ],
        ),
      );
    },
  );

  Widget _outside(Json lobby) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Align(alignment: Alignment.centerLeft, child: BackSquare()),
          const SizedBox(height: 16),
          Text('Match', style: d(24)),
          const SizedBox(height: 4),
          Text('Only approved players can see the squad chat.', style: t(14, c: C.muted)),
          const SizedBox(height: 16),
          LobbyCard(
            lobby: lobby,
            onAction: () => openLobby(context, lobby, onChanged: _cubit.reload),
          ),
        ],
      ),
    ),
  );

  Widget _header(Json lobby) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 8),
      child: Row(
        children: [
          const BackSquare(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lobby['venue']['name'], style: d(18), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${lobby['sport']['name']} · ${lobby['date_label']} · ${lobby['time_label']} · ${lobby['court']['name']}',
                  style: t(12, c: C.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SquareIconButton(LucideIcons.ellipsis, label: 'Match options', onTap: () => _menu(lobby)),
        ],
      ),
    );
  }

  /// Pinned Match Header: Turf Locked / Unbooked badge, Paid counter, Booking QR / PIN, arrival controls.
  Widget _pinned(Json lobby) {
    final me = asMap(lobby['me']);
    final pool = asMap(lobby['pool']);
    final payout = asMap(lobby['payout']);
    final booking = lobby['booking'];
    final crowdfunding = lobby['status'] == 'crowdfunding';
    final paid = (lobby['paid_count'] ?? 0) as int, cap = (lobby['capacity'] ?? 0) as int;
    final payoutText = switch (payout['status']) {
      'held' => 'Shares held in escrow · released to the host at check-in',
      'released' => 'Shares released to the host · ${payout['at'] ?? ''}',
      'settled' => 'Pool paid to the venue',
      'disputed' => 'No-show reported · payout on hold',
      'refunded' => 'Refunded',
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: shadowCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SlotStatePill(lobby),
              const SizedBox(width: 6),
              if (lobby['is_public'] == true && lobby['status'] != 'completed')
                Pill('${lobby['spots_left']} open', bg: C.limeSoft, fg: C.green700),
              const Spacer(),
              const Icon(LucideIcons.circleCheck, size: 15, color: C.green700),
              const SizedBox(width: 4),
              Text('Paid $paid/$cap', style: t(13, w: FontWeight.w700)),
            ],
          ),
          if (crowdfunding) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Pool for the turf', style: t(12, c: C.muted))),
                Text('${inr(pool['pooled'])} of ${inr(pool['target'])}', style: t(12, w: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            FillBar(taken: (pool['pooled'] ?? 0) as int, capacity: (pool['target'] ?? 1) as int),
          ],
          if (payoutText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(LucideIcons.shieldCheck, size: 14, color: C.green700),
                const SizedBox(width: 6),
                Expanded(child: Text(payoutText, style: t(12, c: C.mutedInk))),
              ],
            ),
          ],
          if (booking != null || me['can_checkin'] == true || me['can_report'] == true) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (booking != null)
                  Expanded(
                    child: GhostButton(
                      'Booking QR / PIN',
                      icon: LucideIcons.qrCode,
                      height: 40,
                      radius: 12,
                      fontSize: 13,
                      onTap: () => _showPass(asMap(booking)),
                    ),
                  ),
                if (me['can_checkin'] == true) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(
                      'Check in here',
                      icon: LucideIcons.mapPinCheck,
                      height: 40,
                      radius: 12,
                      fontSize: 13,
                      bg: C.mint,
                      fg: C.green700,
                      border: Colors.transparent,
                      onTap: _checkin,
                    ),
                  ),
                ],
                if (me['can_report'] == true) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: GhostButton(
                      'Report no-show',
                      icon: LucideIcons.flag,
                      height: 40,
                      radius: 12,
                      fontSize: 13,
                      fg: C.redInk,
                      border: C.redSoft,
                      onTap: _report,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _banners(Json lobby, MatchRoomState st) {
    final out = <Widget>[];
    final me = asMap(lobby['me']);
    final host = asMap(lobby['host_actions']);
    Widget banner({
      required IconData icon,
      required Color bg,
      required Color fg,
      required String title,
      required String body,
      List<Widget> actions = const [],
    }) => Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t(14, w: FontWeight.w700, c: fg)),
                    const SizedBox(height: 2),
                    Text(body, style: t(12, c: fg, h: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: a)]]),
          ],
        ],
      ),
    );
    Widget act(String label, VoidCallback onTap, {bool primary = false}) => GhostButton(
      label,
      height: 38,
      radius: 12,
      fontSize: 12,
      bg: primary ? C.brand : Colors.white,
      fg: primary ? Colors.white : C.ink,
      border: Colors.transparent,
      onTap: onTap,
    );

    if (st.isHost && lobby['alert'] == 'slot_taken') {
      out.add(
        banner(
          icon: LucideIcons.triangleAlert,
          bg: C.redSoft,
          fg: C.redInk,
          title: 'Another group booked this slot',
          body: 'Move your squad to another slot, or cancel — everyone who paid is refunded automatically.',
          actions: [act('Switch slot', () => _switchSlot(lobby), primary: true), act('Cancel match', _cancelMatch)],
        ),
      );
    } else if (st.isHost && lobby['alert'] == 'unfilled') {
      out.add(
        banner(
          icon: LucideIcons.timer,
          bg: C.amberSoft,
          fg: C.amber,
          title: 'Kickoff soon — the pool is short',
          body: 'Pay the remaining ${inr(host['pay_balance'])} to lock the turf now, switch slot, or unpublish '
              '(solo players are refunded, your squad chat stays).',
          actions: [
            if (host['pay_balance'] != null)
              act('Pay ${inr(host['pay_balance'])}', () => _payBalance(host['pay_balance']), primary: true),
            act('Switch slot', () => _switchSlot(lobby)),
            if (host['can_unpublish'] == true) act('Unpublish', _unpublish),
          ],
        ),
      );
    }
    if (st.isHost && lobby['held_booking'] != null) {
      out.add(
        banner(
          icon: LucideIcons.lockOpen,
          bg: C.orangeBg,
          fg: C.orangeInk,
          title: 'Turf not locked yet',
          body: 'Finish paying for the slot to lock it. The hold expires in a few minutes.',
          actions: [act('Pay & lock turf', () => _resumeHostPayment(lobby['held_booking']), primary: true)],
        ),
      );
    } else if (st.isHost && host['can_lock'] == true && lobby['alert'] != 'slot_taken') {
      out.add(
        banner(
          icon: LucideIcons.lockOpen,
          bg: C.coralSoft,
          fg: C.orangeInk,
          title: 'Turf not booked yet',
          body: 'Get your squad together first. Pay ${inr(host['lock_amount'])} to lock the slot when you\'re ready — '
              'until then another group can still book it.',
          actions: [
            act('Lock turf', _lockTurf, primary: true),
            if (host['can_switch'] == true) act('Switch slot', () => _switchSlot(lobby)),
          ],
        ),
      );
    }
    if (me['can_pay'] == true) {
      final until = DateTime.tryParse(me['pay_by'] ?? '');
      out.add(
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.brand, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your share · ${inr(me['amount_due'])}', style: t(14, w: FontWeight.w700)),
                    if (until != null)
                      Countdown(
                        until: until,
                        builder: (_, left) => Text(
                          'Pay within ${mmss(left)} or the spot reopens',
                          style: t(12, c: left.inMinutes < 5 ? C.redInk : C.muted),
                        ),
                      )
                    else
                      Text('Paid into escrow, not to the host', style: t(12, c: C.muted)),
                  ],
                ),
              ),
              PrimaryButton('Pay now', height: 42, radius: 12, fontSize: 14, shadow: false, onTap: _pay),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _players(Json lobby, MatchRoomState st) {
    final members = asList(lobby['members']);
    final open = (lobby['spots_left'] ?? 0) as int;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final (i, m) in members.indexed)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: C.line),
            ),
            child: Row(
              children: [
                Avatar(m['initials'] ?? '', size: 36, index: i),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m['name']}${m['is_me'] == true ? ' (you)' : ''}', style: t(14, w: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _tag(m['tag']),
                          const SizedBox(width: 6),
                          if (m['checked_in'] == true) ...[
                            const Icon(LucideIcons.mapPinCheck, size: 12, color: C.green700),
                            const SizedBox(width: 2),
                            Text('Checked in', style: t(11, c: C.green700)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (m['status'] == 'invited')
                  const Pill('Invited', bg: C.chip, fg: C.muted)
                else if (m['paid'] == true)
                  const Pill('Paid', bg: C.mint, fg: C.green700)
                else
                  Pill('Due ${inr(m['amount_due'])}', bg: C.amberSoft, fg: C.amber),
                if (st.isHost && m['tag'] != 'host')
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LucideIcons.userX, size: 18, color: C.muted),
                    onPressed: () async {
                      if (!await _confirm(
                        'Remove ${m['name']}?',
                        'Anything they paid is refunded in full and the spot opens again.',
                        'Remove player',
                      )) {
                        return;
                      }
                      try {
                        await _cubit.removeMember(m['id']);
                      } catch (e) {
                        if (mounted) toast(context, e.toString());
                      }
                    },
                  ),
              ],
            ),
          ),
        if (open > 0)
          DashedBorderBox(
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(LucideIcons.userPlus, size: 18, color: C.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lobby['is_public'] == true
                          ? '$open open spot${open == 1 ? '' : 's'} — listed for solo players'
                          : '$open open spot${open == 1 ? '' : 's'}',
                      style: t(13, c: C.mutedInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tag(String? tag) {
    final (label, bg, fg) = switch (tag) {
      'host' => ('Host', C.mint, C.green700),
      'known' => ('Known', C.blueSoft, C.blue),
      'guest' => ('Guest', C.amberSoft, C.amber),
      _ => ('Solo', C.purpleSoft, C.purple),
    };
    return Pill(label, bg: bg, fg: fg, size: 10, padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2));
  }

  /// Host Request Screening: every solo request with attendance stats → 1-on-1 thread.
  Widget _requests(MatchRoomState st) {
    final reqs = st.requests;
    if (reqs == null) return const ListSkeleton(count: 3, circle: true);
    if (reqs.isEmpty) {
      return const SingleChildScrollView(
        child: EmptyNote(
          icon: LucideIcons.inbox,
          title: 'No requests yet',
          body: 'Solo players who ask to join show up here. You chat 1-on-1 before letting them into the squad chat.',
        ),
      );
    }
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _cubit.loadRequests,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final r in reqs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await context.pushRequestThread(_cubit.lobbyId, r['id']);
                    _cubit.reload();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: r['status'] == 'pending' ? C.brand : C.line),
                    ),
                    child: Row(
                      children: [
                        Avatar(r['player']['initials'] ?? '', size: 40, index: (r['player']['id'] ?? 0) as int),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['player']['name'] ?? '', style: t(14, w: FontWeight.w700)),
                              Text(attendanceLine(asMap(r['player'])), style: t(12, c: C.green700)),
                              if ((r['last_message'] ?? '').toString().isNotEmpty)
                                Text(
                                  r['last_message'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t(12, c: C.muted),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        switch (r['status']) {
                          'pending' => const Pill('Review', bg: C.brand, fg: Colors.white),
                          'approved' => const Pill('Approved'),
                          _ => const Pill('Declined', bg: C.chip, fg: C.muted),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "12 games · 92% attendance · 1 drop-off" / "New player".
String attendanceLine(Json p) {
  if (p['score'] == null) return p['played'] == 0 ? 'New player · no games yet' : '${p['played']} games played';
  final drops = (p['drop_offs'] ?? 0) as int;
  return '${p['played']} games · ${p['score']}% attendance${drops > 0 ? ' · $drops drop-off${drops == 1 ? '' : 's'}' : ''}';
}

/// Host: move a crowdfunding lobby to another free slot on the same court.
class _SwitchSlotSheet extends StatefulWidget {
  final Json lobby;
  const _SwitchSlotSheet({required this.lobby});
  @override
  State<_SwitchSlotSheet> createState() => _SwitchSlotSheetState();
}

class _SwitchSlotSheetState extends State<_SwitchSlotSheet> {
  int day = 0;
  List<Json>? slots;
  String? error;

  DateTime get _date {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: day));
  }

  @override
  void initState() {
    super.initState();
    final current = DateTime.tryParse(widget.lobby['date'] ?? '');
    if (current != null) {
      final n = DateTime.now();
      day = current.difference(DateTime(n.year, n.month, n.day)).inDays.clamp(0, 13);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => slots = null);
    try {
      final r = await context.read<VenueRepository>().availability(
        widget.lobby['venue']['id'],
        date: DateFormat('yyyy-MM-dd').format(_date),
        sportId: widget.lobby['sport']['id'],
        courtId: widget.lobby['court']['id'],
      );
      if (mounted) setState(() => slots = asList(r['slots']));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  bool _fits(int start) {
    final dur = (widget.lobby['duration'] ?? 1) as int;
    for (var h = start; h < start + dur; h++) {
      final s = slots!.where((x) => x['hour'] == h).firstOrNull;
      final mine = DateFormat('yyyy-MM-dd').format(_date) == widget.lobby['date'] &&
          h >= widget.lobby['start_hour'] &&
          h < widget.lobby['start_hour'] + dur;
      if (s == null || (s['status'] != 'free' && !mine)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Switch slot', style: d(22)),
        const SizedBox(height: 4),
        Text('${widget.lobby['court']['name']} · ${widget.lobby['duration']} hr · everyone is notified', style: t(13, c: C.muted)),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 14,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final dd = DateTime(n.year, n.month, n.day).add(Duration(days: i));
              return Choice(
                selected: i == day,
                height: 40,
                radius: 12,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onTap: () {
                  setState(() => day = i);
                  _load();
                },
                child: Text(
                  i == 0 ? 'Today' : DateFormat('EEE d').format(dd),
                  style: t(13, w: FontWeight.w600, c: i == day ? Colors.white : C.ink),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (error != null)
          Text(error!, style: t(13, c: C.redInk))
        else if (slots == null)
          const SlotGridSkeleton()
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in slots!)
                if (s['status'] != 'past' && _fits(s['hour']))
                  GestureDetector(
                    onTap: () => Navigator.pop(context, {
                      'date': DateFormat('yyyy-MM-dd').format(_date),
                      'start_hour': s['hour'],
                    }),
                    child: Container(
                      width: 78,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.radioOff, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Text(s['label'], style: t(13, w: FontWeight.w700)),
                          Text(inr(s['price']), style: t(10, c: C.muted)),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}
