import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import 'lobby_widgets.dart';

/// Messages, newest at the bottom. System notes are centred, payment cards are pinned-style cards.
class ChatList extends StatelessWidget {
  final List<Json> messages;
  final ScrollController controller;

  /// Tapped "Pay" on my own payment card.
  final VoidCallback? onPay;
  final String emptyText;
  const ChatList({super.key, required this.messages, required this.controller, this.onPay, this.emptyText = 'Say hi 👋'});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(child: Text(emptyText, style: t(14, c: C.muted)));
    }
    return ListView.builder(
      controller: controller,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[messages.length - 1 - i];
        final prev = i + 1 < messages.length ? messages[messages.length - 2 - i] : null;
        final grouped = prev != null && prev['kind'] == 'text' && prev['sender']?['id'] == m['sender']?['id'];
        return switch (m['kind']) {
          'system' => _SystemNote(m),
          'payment' => PaymentCard(message: m, onPay: onPay),
          _ => _Bubble(m, showName: !grouped),
        };
      },
    );
  }
}

class _SystemNote extends StatelessWidget {
  final Json m;
  const _SystemNote(this.m);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: C.segment, borderRadius: BorderRadius.circular(12)),
        child: Text(m['body'] ?? '', textAlign: TextAlign.center, style: t(12, c: C.mutedInk, h: 1.4)),
      ),
    ),
  );
}

class _Bubble extends StatelessWidget {
  final Json m;
  final bool showName;
  const _Bubble(this.m, {required this.showName});

  @override
  Widget build(BuildContext context) {
    final sender = asMap(m['sender']);
    final mine = sender['is_me'] == true;
    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 3),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            showName ? Avatar(sender['initials'] ?? '', size: 28, index: (sender['id'] ?? 0) as int) : const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: mine ? C.brand : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: C.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine && showName)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(sender['name'] ?? '', style: t(12, w: FontWeight.w700, c: C.green700)),
                    ),
                  Text(m['body'] ?? '', style: t(14, c: mine ? Colors.white : C.ink, h: 1.4)),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(m['at'] ?? '', style: t(10, c: mine ? Colors.white70 : C.muted)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// In-chat UPI payment card. Solo joiners get a strict 15-minute countdown.
class PaymentCard extends StatelessWidget {
  final Json message;
  final VoidCallback? onPay;
  const PaymentCard({super.key, required this.message, this.onPay});

  @override
  Widget build(BuildContext context) {
    final card = asMap(message['card']);
    final status = card['status'];
    final paid = status == 'confirmed';
    final open = status == 'pending';
    final mine = card['is_me'] == true;
    final until = DateTime.tryParse(card['pay_by'] ?? '');
    final (bg, border) = paid
        ? (C.mint, const Color(0xFFBBF7D0))
        : open
        ? (Colors.white, C.brand)
        : (C.chip, C.line);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: open && mine ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  paid ? LucideIcons.circleCheck : LucideIcons.chevronsRight,
                  size: 18,
                  color: paid ? C.green700 : C.brand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    paid
                        ? '${card['name']} paid ${inr(card['amount'])}'
                        : open
                        ? '${mine ? 'Your share' : '${card['name']}\'s share'} · ${inr(card['amount'])}'
                        : '${card['name']} · payment closed',
                    style: t(14, w: FontWeight.w700),
                  ),
                ),
                if (open && until != null)
                  Countdown(
                    until: until,
                    builder: (_, left) => Pill(
                      mmss(left),
                      bg: left.inMinutes < 5 ? C.redSoft : C.amberSoft,
                      fg: left.inMinutes < 5 ? C.redInk : C.amber,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              paid
                  ? 'Held safely in Turflet escrow.'
                  : open
                  ? (until != null
                        ? 'UPI · pay within 15 minutes or the spot reopens for someone else.'
                        : 'UPI · paid into escrow, never to the host directly.')
                  : 'This spot was released.',
              style: t(12, c: C.muted, h: 1.4),
            ),
            if (open && mine && onPay != null) ...[
              const SizedBox(height: 10),
              PrimaryButton('Pay ${inr(card['amount'])} with UPI', height: 46, radius: 14, shadow: false, onTap: onPay),
            ],
          ],
        ),
      ),
    );
  }
}

/// Text field + send button pinned above the keyboard.
class Composer extends StatefulWidget {
  final Future<bool> Function(String body) onSend;
  final String hint;

  /// Pad for the home indicator; off when an action bar sits below.
  final bool safeBottom;
  const Composer({super.key, required this.onSend, this.hint = 'Message the squad', this.safeBottom = true});

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final controller = TextEditingController();
  bool busy = false;

  Future<void> _send() async {
    final body = controller.text.trim();
    if (body.isEmpty || busy) return;
    setState(() => busy = true);
    final ok = await widget.onSend(body);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) controller.clear();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + (widget.safeBottom ? MediaQuery.of(context).padding.bottom : 0)),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: C.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.ground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: C.line),
            ),
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: t(14),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: widget.hint,
                hintStyle: t(14, c: C.muted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Send',
          child: GestureDetector(
            onTap: _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: C.brand, shape: BoxShape.circle),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(LucideIcons.send, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    ),
  );
}
