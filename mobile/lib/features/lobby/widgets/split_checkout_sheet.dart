import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/lobby_repository.dart';
import 'lobby_widgets.dart';

/// 7 · Split Checkout & Escrow: itemised turf share + platform fee, one-tap UPI, escrow protection.
/// Resolves to the updated lobby once paid, or null.
Future<Json?> showSplitCheckout(BuildContext context, {required int lobbyId}) =>
    sheet<Json>(context, (_) => _CheckoutSheet(lobbyId: lobbyId));

/// Host option when a crowdfunding lobby is short near kickoff: pay what the pool is missing.
Future<Json?> showPayBalance(BuildContext context, {required int lobbyId, required int amount}) =>
    sheet<Json>(context, (_) => _CheckoutSheet(lobbyId: lobbyId, balance: amount));

class _CheckoutSheet extends StatefulWidget {
  final int lobbyId;
  final int? balance;
  const _CheckoutSheet({required this.lobbyId, this.balance});
  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  Json? quote;
  String? error;
  String method = 'upi';
  final upi = TextEditingController();
  bool busy = false;

  LobbyRepository get _repo => context.read<LobbyRepository>();
  bool get _balance => widget.balance != null;

  @override
  void initState() {
    super.initState();
    if (_balance) {
      quote = {'total': widget.balance};
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final q = await _repo.checkout(widget.lobbyId);
      if (mounted) setState(() => quote = q);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _pay() async {
    setState(() => busy = true);
    try {
      final r = _balance
          ? await _repo.action(widget.lobbyId, 'pay-balance', {'method': method, 'upi_id': upi.text.trim()})
          : await _repo.pay(widget.lobbyId, method: method, upiId: upi.text.trim());
      if (!mounted) return;
      context.read<AppCubit>().refreshMe(); // wallet may have changed
      Navigator.pop(context, r);
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    upi.dispose();
    super.dispose();
  }

  Widget _option(String id, String title, String sub, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Choice(
      selected: method == id,
      filled: false,
      selBg: Colors.white,
      selWidth: 2,
      height: 60,
      onTap: () => setState(() => method = id),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: C.green700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t(14, w: FontWeight.w600)),
                Text(sub, style: t(12, c: C.muted)),
              ],
            ),
          ),
          RadioDot(method == id),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return ErrorRetry(
        error!,
        onRetry: () {
          setState(() => error = null);
          _load();
        },
      );
    }
    final q = quote;
    if (q == null) return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator(color: C.brand)));
    final wallet = context.watch<AppCubit>().state.user?['wallet_balance'] ?? 0;
    final until = DateTime.tryParse(q['pay_by'] ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(_balance ? 'Pay the balance' : 'Split checkout', style: d(22))),
            if (until != null)
              Countdown(
                until: until,
                builder: (_, left) => Pill(
                  '${mmss(left)} left',
                  bg: left.inMinutes < 5 ? C.redSoft : C.amberSoft,
                  fg: left.inMinutes < 5 ? C.redInk : C.amber,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        CardBox(
          shadow: null,
          border: Border.all(color: C.line),
          child: Column(
            children: [
              if (_balance)
                PriceRow('Missing from the pool', inr(q['total']))
              else ...[
                PriceRow('Your turf share', inr(q['turf_share'])),
                if ((q['guests'] ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  PriceRow('Your guests (${q['guests']} × ${inr(q['turf_share'])})', inr(q['guest_shares'])),
                ],
                const SizedBox(height: 8),
                PriceRow('Platform fee', inr(q['platform_fee'])),
              ],
              const SizedBox(height: 12),
              PriceRow('Total', inr(q['total']), bold: true, top: true, size: 16),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.limeSoft, borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.shieldCheck, size: 18, color: C.green700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _balance
                      ? 'The turf is booked as soon as you pay. Players who still pay their share recover your money '
                            'through escrow.'
                      : q['escrow_note'] ?? '',
                  style: t(12, c: C.green900, h: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _option('upi', 'UPI', 'One tap with any UPI app', LucideIcons.chevronsRight),
        if (method == 'upi')
          Container(
            height: 46,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.ground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: C.line),
            ),
            child: TextField(
              controller: upi,
              keyboardType: TextInputType.emailAddress,
              style: t(14),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'UPI ID (optional), e.g. yourname@bank',
                hintStyle: t(14, c: C.muted),
              ),
            ),
          ),
        _option('wallet', 'Turflet balance', 'Balance ${inr(wallet)}', LucideIcons.wallet),
        const SizedBox(height: 8),
        PrimaryButton('Pay ${inr(q['total'])}', loading: busy, onTap: _pay),
      ],
    );
  }
}
