import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_state.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/support_repository.dart';
import '../../auth/auth_guard.dart';
import '../../shell/widgets/bottom_nav.dart';
import '../cubit/help_cubit.dart';

/// 12 · Help & support (in Profile). [booking] pre-selects the booking a ticket is about.
class HelpScreen extends StatelessWidget {
  final Json? booking;
  const HelpScreen({super.key, this.booking});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => HelpCubit(
      booking: booking,
      support: c.read<SupportRepository>(),
      bookings: c.read<BookingRepository>(),
      app: c.read<AppCubit>(),
    )..load(),
    child: const _HelpView(),
  );
}

class _HelpView extends StatefulWidget {
  const _HelpView();
  @override
  State<_HelpView> createState() => _HelpViewState();
}

/// Which FAQ is expanded is view-only state.
class _HelpViewState extends State<_HelpView> {
  int open = 0;

  void _chat() {
    final ctl = TextEditingController();
    var busy = false;
    sheet(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Message support', style: d(22)),
              const SizedBox(height: 6),
              Text(context.read<AppCubit>().state.config['support']?['reply_time'] ?? '', style: t(13, c: C.muted)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: C.ground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line),
                ),
                child: TextField(
                  controller: ctl,
                  autofocus: true,
                  maxLines: 4,
                  style: t(15),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'How can we help?',
                    hintStyle: t(15, c: C.muted),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                'Send',
                height: 52,
                loading: busy,
                onTap: () async {
                  if (ctl.text.trim().isEmpty) return;
                  final help = context.read<HelpCubit>();
                  if (!await requireLogin(context)) return;
                  set(() => busy = true);
                  try {
                    await help.sendMessage(ctl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) toast(context, "Message sent. We'll reply shortly.");
                  } catch (e) {
                    set(() => busy = false);
                    if (mounted) toast(context, e.toString());
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<HelpCubit, HelpState>(builder: _build);

  Widget _build(BuildContext context, HelpState st) {
    final faqs = st.faqs, upcoming = st.upcoming;
    final sup = asMap(context.watch<AppCubit>().state.config['support']);
    final cfg = context.watch<AppCubit>().state.config;
    final top = MediaQuery.of(context).padding.top;
    return WithNav(
      current: AppTab.profile,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 26),
            decoration: const BoxDecoration(
              color: C.limeSoft,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.chevronLeft, size: 16, color: C.brandDark),
                        Text(
                          'Back',
                          style: t(13, w: FontWeight.w600, c: C.brandDark),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Help & support', style: d(28, ls: -0.5)),
                const SizedBox(height: 6),
                Text(sup['reply_time'] ?? 'We usually reply in under 5 minutes.', style: t(14, c: C.mutedInk)),
                const SizedBox(height: 18),
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: shadowCard),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.search, size: 18, color: C.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          style: t(15),
                          onChanged: (v) => context.read<HelpCubit>().search(v.trim()),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            hintText: 'Search e.g. refund, reschedule',
                            hintStyle: t(15, c: C.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (upcoming != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.pushTicket(upcoming['id']),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: shadowSoft,
                      color: Colors.white,
                    ),
                    child: Row(
                      children: [
                        Img(upcoming['venue']['image'], width: 56, height: 56, radius: BorderRadius.circular(14)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HELP WITH UPCOMING BOOKING',
                                style: t(11, w: FontWeight.w700, c: C.green700, ls: 0.4),
                              ),
                              const SizedBox(height: 2),
                              Text(upcoming['venue']['name'], style: t(14, w: FontWeight.w700)),
                              Text(
                                '${upcoming['date_label']} · ${upcoming['time_short']} · ${upcoming['code']}',
                                style: t(12, c: C.muted),
                              ),
                            ],
                          ),
                        ),
                        const Icon(LucideIcons.chevronRight, size: 18, color: C.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Label('Contact us', padding: EdgeInsets.fromLTRB(20, 22, 20, 10)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _contact(LucideIcons.messageCircle, C.mint, C.green700, 'Chat', sup['chat_hours'] ?? '24 × 7', _chat),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contact(
                    LucideIcons.phone,
                    C.blueSoft,
                    C.blue,
                    'Call',
                    sup['call_hours'] ?? '',
                    () => launchUrl(Uri(scheme: 'tel', path: sup['phone'] ?? '')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _contact(
                    LucideIcons.mail,
                    C.purpleSoft,
                    C.purple,
                    'Email',
                    sup['email_sla'] ?? '',
                    () => launchUrl(Uri(scheme: 'mailto', path: sup['email'] ?? '', query: 'subject=Turflet help')),
                  ),
                ),
              ],
            ),
          ),
          const Label('Popular questions', padding: EdgeInsets.fromLTRB(20, 22, 20, 10)),
          CardBox(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < faqs.length; i++)
                  Container(
                    decoration: i < faqs.length - 1
                        ? const BoxDecoration(
                            border: Border(bottom: BorderSide(color: C.divider)),
                          )
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => open = open == i ? -1 : i),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 56),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(faqs[i]['q'], style: t(14, w: FontWeight.w600, h: 1.35)),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: open == i ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(LucideIcons.chevronDown, size: 18, color: C.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (open == i)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(faqs[i]['a'], style: t(13, c: C.muted, h: 1.6)),
                          ),
                      ],
                    ),
                  ),
                if (faqs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No matching questions.', style: t(14, c: C.muted)),
                  ),
              ],
            ),
          ),
          const Label('Policies', padding: EdgeInsets.fromLTRB(20, 22, 20, 10)),
          CardBox(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _policy(
                  LucideIcons.receipt,
                  C.orangeSoft,
                  C.orange,
                  'Refund & cancellation policy',
                  'Refund timelines and charges',
                  0,
                  true,
                ),
                _policy(LucideIcons.shield, C.tealSoft, C.teal, 'Privacy policy', 'How we handle your data', 1, true),
                _policy(LucideIcons.fileText, C.chip, C.muted, 'Terms of use', 'Rules for players & venues', 2, false),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text(
              'Turflet v${cfg['app_version'] ?? '1.1'} · Bookings are linked to your verified email',
              textAlign: TextAlign.center,
              style: t(12, c: C.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contact(IconData icon, Color bg, Color fg, String title, String sub, VoidCallback onTap) => Container(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: shadowSoft),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(height: 6),
              Text(title, style: t(13, w: FontWeight.w600)),
              Text(sub, style: t(11, c: C.muted)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _policy(IconData icon, Color bg, Color fg, String title, String sub, int tab, bool border) => InkWell(
    onTap: () => context.pushPolicy(tab: tab),
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: border
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: C.divider)),
            )
          : null,
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
                Text(title, style: t(14, w: FontWeight.w600)),
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
