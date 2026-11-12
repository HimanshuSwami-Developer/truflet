import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'success.dart';

/// 7 · Review & pay
class PaymentScreen extends StatefulWidget {
  final Json booking;
  const PaymentScreen({super.key, required this.booking});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

const _methods = [
  ('upi', 'UPI', 'UPI', 'Pay from any UPI app', LucideIcons.chevronsRight),
  ('card', 'Credit / Debit card', 'Card', 'Visa, Mastercard, RuPay', LucideIcons.creditCard),
  ('net', 'Net banking', 'Net banking', 'All major banks', LucideIcons.landmark),
  ('wallet', 'Wallets', 'Wallet', 'Turflet balance', LucideIcons.wallet),
];

class _PaymentScreenState extends State<PaymentScreen> {
  late Json b = widget.booking;
  String method = 'upi';
  final code = TextEditingController();
  final upi = TextEditingController();
  bool busy = false, couponBusy = false;
  String? couponError;
  Timer? timer;
  Duration left = Duration.zero;

  @override
  void initState() {
    super.initState();
    code.text = b['coupon'] ?? '';
    _tick();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final until = DateTime.tryParse(b['held_until'] ?? '');
    if (until == null) return;
    final d = until.difference(DateTime.now());
    setState(() => left = d.isNegative ? Duration.zero : d);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _coupon() async {
    final applied = b['coupon'] != null;
    setState(() {
      couponBusy = true;
      couponError = null;
    });
    try {
      final r = asMap(await api.post('/bookings/${b['id']}/coupon/', {'code': applied ? '' : code.text.trim()}));
      setState(() {
        b = r;
        if (applied) code.clear();
      });
    } catch (e) {
      setState(() => couponError = e.toString());
    } finally {
      setState(() => couponBusy = false);
    }
  }

  Future<void> _pay() async {
    if (left == Duration.zero) {
      toast(context, 'Your slot hold expired. Please pick the slot again.');
      return;
    }
    setState(() => busy = true);
    try {
      final r = asMap(await api.post('/bookings/${b['id']}/pay/', {'method': method, 'upi_id': upi.text.trim()}));
      if (!mounted) return;
      context.read<AppState>().refreshMe();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SuccessScreen(booking: r)));
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final applied = b['coupon'] != null;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    final short = _methods.firstWhere((m) => m.$1 == method).$3;
    final wallet = context.watch<AppState>().user?['wallet_balance'] ?? 0;
    final peak = (b['peak_hours'] ?? 0) > 0;
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
          child: Row(children: [
            const BackSquare(),
            const SizedBox(width: 12),
            Text('Review & pay', style: d(20)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(999)),
              child: Row(children: [
                const Icon(LucideIcons.clock, size: 14, color: C.warnInk),
                const SizedBox(width: 6),
                Text(left == Duration.zero ? 'Hold expired' : 'Slot held $mm:$ss', style: t(12, w: FontWeight.w600, c: C.warnInk)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: shadowCard),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Img(b['venue']['image'], width: 72, height: 72, radius: BorderRadius.circular(16)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['venue']['name'], style: d(17)),
                        const SizedBox(height: 4),
                        Text('${b['venue']['area']}, ${b['venue']['city']}', style: t(13, c: C.muted)),
                        const SizedBox(height: 4),
                        SportPill(b['sport'], label: '${b['sport']['name']} · ${b['court']['name']}'),
                      ]),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Edit', style: t(13, w: FontWeight.w600, c: C.brand))),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: const BoxDecoration(color: C.ground, border: Border(top: BorderSide(color: C.dashed))),
                  child: Row(children: [
                    Expanded(child: KV('Date', b['date_label'].toString().replaceFirst('Today, ', 'Today, '), vSize: 13)),
                    Expanded(child: KV('Time', b['time_short'], vSize: 13)),
                    Expanded(child: KV('Duration', '${b['duration']} ${b['duration'] == 1 ? 'hr' : 'hrs'}', vSize: 13)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Have a coupon?', style: t(13, w: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                      child: TextField(
                        controller: code,
                        enabled: !applied,
                        textCapitalization: TextCapitalization.characters,
                        style: t(14),
                        decoration: InputDecoration(border: InputBorder.none, hintText: 'Enter code', hintStyle: t(14, c: C.muted)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: Material(
                      color: applied ? C.mint : C.brand,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: couponBusy ? null : _coupon,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Center(
                            child: Text(applied ? 'Remove' : 'Apply', style: t(14, w: FontWeight.w700, c: applied ? C.brand : Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                if (couponError != null)
                  Text(couponError!, style: t(12, c: C.warnInk))
                else if (applied)
                  Text('${b['coupon']} applied — you save ${inr(b['discount'])}', style: t(13, w: FontWeight.w600, c: C.brand))
                else
                  Text.rich(TextSpan(style: t(12, c: C.muted), children: [
                    const TextSpan(text: 'Try '),
                    TextSpan(text: 'PLAY100', style: t(12, w: FontWeight.w700)),
                    const TextSpan(text: ' for ₹100 off your first booking'),
                  ])),
              ]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: C.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const H2('Price details', size: 16),
                const SizedBox(height: 14),
                PriceRow('Slot charges (${b['duration']} × ${inr(b['rate'])}${peak ? ' peak' : ''})', inr(b['slot_amount'])),
                const SizedBox(height: 10),
                PriceRow('Convenience fee', inr(b['convenience_fee'])),
                const SizedBox(height: 10),
                PriceRow('GST on fee (${(context.read<AppState>().config['gst_percent'] ?? 18).round()}%)', inr(b['gst'])),
                if (applied) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text('Coupon discount', style: t(14, w: FontWeight.w600, c: C.brand))),
                    Text('−${inr(b['discount'])}', style: t(14, w: FontWeight.w600, c: C.brand)),
                  ]),
                ],
                const SizedBox(height: 10),
                PriceRow('To pay', inr(b['total']), bold: true, top: true, size: 16),
              ]),
            ),
            const SizedBox(height: 16),
            const H2('Pay with', size: 16),
            const SizedBox(height: 10),
            for (final m in _methods) ...[
              _method(m, wallet),
              const SizedBox(height: 10),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(LucideIcons.shieldCheck, size: 14, color: C.muted),
              const SizedBox(width: 6),
              Flexible(child: Text('100% secure payments · Free cancellation up to 6 hrs before', style: t(12, c: C.muted))),
            ]),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
          child: Container(
            height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: shadowBrand),
            child: Material(
              color: C.brand,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: busy ? null : _pay,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: busy
                      ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4)))
                      : Row(children: [
                          Text('Pay ${inr(b['total'])}', style: t(16, w: FontWeight.w700, c: Colors.white)),
                          const Spacer(),
                          Text('via $short', style: t(14, w: FontWeight.w600, c: Colors.white)),
                          const SizedBox(width: 6),
                          const Icon(LucideIcons.arrowRight, size: 18, color: Colors.white),
                        ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _method((String, String, String, String, IconData) m, int wallet) {
    final on = m.$1 == method;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? C.brand : C.line, width: on ? 2 : 1),
      ),
      child: Column(children: [
        Semantics(
          checked: on,
          inMutuallyExclusiveGroup: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => method = m.$1),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(12)),
                  child: Icon(m.$5, size: 20, color: C.green700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.$2, style: t(15, w: FontWeight.w600)),
                    Text(m.$1 == 'wallet' ? 'Turflet balance ${inr(wallet)}' : m.$4, style: t(12, c: C.muted)),
                  ]),
                ),
                RadioDot(on),
              ]),
            ),
          ),
        ),
        if (on && m.$1 == 'upi')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('UPI ID', style: t(12, c: C.muted)),
              const SizedBox(height: 6),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: C.ground, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
                child: TextField(
                  controller: upi,
                  keyboardType: TextInputType.emailAddress,
                  style: t(14),
                  decoration: InputDecoration(border: InputBorder.none, hintText: 'yourname@bank', hintStyle: t(14, c: C.muted)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
