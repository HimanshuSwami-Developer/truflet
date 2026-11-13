import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_state.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/external_actions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';

/// 8 · Booking confirmed
class BookingConfirmedScreen extends StatefulWidget {
  final Json booking;
  const BookingConfirmedScreen({super.key, required this.booking});
  @override
  State<BookingConfirmedScreen> createState() => _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState extends State<BookingConfirmedScreen> with SingleTickerProviderStateMixin {
  late final pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();

  @override
  void dispose() {
    pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -140,
            left: -60,
            right: -60,
            child: Container(
              height: 360,
              decoration: const BoxDecoration(
                color: C.limeSoft,
                borderRadius: BorderRadius.vertical(bottom: Radius.elliptical(255, 180)),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, top + 28, 20, 20),
                  children: [
                    Center(
                      child: ScaleTransition(
                        scale: CurvedAnimation(parent: pop, curve: Curves.elasticOut),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(
                            color: C.brand,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Color(0x26143D2B), spreadRadius: 10),
                              BoxShadow(color: Color(0x40143D2B), blurRadius: 30, offset: Offset(0, 14)),
                            ],
                          ),
                          child: const Icon(LucideIcons.check, color: Colors.white, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Booking confirmed!', textAlign: TextAlign.center, style: d(28, ls: -0.4)),
                    const SizedBox(height: 6),
                    Text(
                      '${inr(b['total'])} paid via ${b['payment_method_label']}. Details sent to your email.',
                      textAlign: TextAlign.center,
                      style: t(14, c: C.muted, h: 1.5),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: shadowBig,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 110,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Img(b['venue']['image']),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: [0.2, 1],
                                        colors: [Colors.transparent, Color(0xA6000000)],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 16,
                                    right: 16,
                                    bottom: 12,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(b['venue']['name'], style: d(18, c: Colors.white)),
                                              Text('${b['venue']['area']}, ${b['venue']['city']}', style: t(12, c: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        const Pill('CONFIRMED', bg: C.lime, fg: C.ink),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: KV('Date', b['date_long'])),
                                    Expanded(child: KV('Time', b['time_long'])),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Court', style: t(11, c: C.muted)),
                                          const SizedBox(height: 2),
                                          Text.rich(
                                            TextSpan(
                                              style: t(14, w: FontWeight.w700),
                                              children: [
                                                TextSpan(text: '${b['court']['name']} · '),
                                                TextSpan(
                                                  text: b['sport']['name'],
                                                  style: t(14, w: FontWeight.w700, c: hex(b['sport']['fg'])),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(child: KV('Booking ID', b['code'])),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Perforation(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 96,
                                  height: 96,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: C.line),
                                  ),
                                  child: QrImageView(
                                    data: b['qr_payload'],
                                    padding: EdgeInsets.zero,
                                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: C.ink),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: C.ink,
                                    ),
                                    semanticsLabel: 'Check-in QR code',
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Show at the counter', style: t(14, w: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Scan this QR at check-in. Please arrive 10 minutes early.',
                                        style: t(12, c: C.muted, h: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: GhostButton('Add to calendar', icon: LucideIcons.calendarPlus, onTap: () => addToCalendar(b)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GhostButton('Invite team', icon: LucideIcons.userPlus, onTap: () => inviteTeam(b)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).padding.bottom / 2),
                child: Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        'Home',
                        height: 56,
                        radius: 18,
                        fontSize: 15,
                        onTap: () => context.goTab(AppTab.explore),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: b['lobby'] != null
                          ? PrimaryButton('Open Match Room', onTap: () => context.replaceWithMatch(b['lobby']['id']))
                          : PrimaryButton('View full ticket', onTap: () => context.replaceWithTicket(b['id'])),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
