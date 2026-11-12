import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/support_repository.dart';
import '../cubit/policy_cubit.dart';

/// 13 · Refund & privacy policy (content managed from the admin panel)
class PolicyScreen extends StatelessWidget {
  final int initialTab;
  const PolicyScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => PolicyCubit(repository: c.read<SupportRepository>())..load(),
    child: _PolicyView(initialTab: initialTab),
  );
}

class _PolicyView extends StatefulWidget {
  final int initialTab;
  const _PolicyView({required this.initialTab});
  @override
  State<_PolicyView> createState() => _PolicyViewState();
}

const _noteIcons = {
  'clock': LucideIcons.clock,
  'refresh': LucideIcons.refreshCw,
  'cloud': LucideIcons.cloudRain,
  'receipt': LucideIcons.receipt,
  'shield': LucideIcons.shield,
  'info': LucideIcons.info,
};
const _noteColors = {
  'blue': (C.blueSoft, C.blue),
  'purple': (C.purpleSoft, C.purple),
  'teal': (C.tealSoft, C.teal),
  'gray': (C.chip, C.muted),
  'green': (C.mint, C.green700),
  'amber': (C.amberSoft, C.amber),
  'orange': (C.orangeSoft, C.orange),
};

/// The selected tab is view-only state.
class _PolicyViewState extends State<_PolicyView> {
  late int tab = widget.initialTab.clamp(0, 2);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final updated = context.watch<AppCubit>().state.config['policy_updated_on'];
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
            child: Row(
              children: [
                const BackSquare(),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Policies', style: d(20)),
                    if (updated != null) Text('Last updated $updated', style: t(12, c: C.muted)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Segmented(
              labels: const ['Refund & cancellation', 'Privacy', 'Terms'],
              index: tab,
              onChanged: (i) => setState(() => tab = i),
            ),
          ),
          Expanded(
            child: DataBuilder<PolicyCubit, Json>(
              skeleton: const TextCardsSkeleton(),
              builder: (context, p) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  if (tab == 0) ..._refund(p),
                  if (tab == 1) ..._privacy(asList(p['privacy']), true),
                  if (tab == 2) ..._privacy(asList(p['terms']), false),
                  const SizedBox(height: 14),
                  DashedBorderBox(
                    radius: 16,
                    color: C.dotOff,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text.rich(
                        TextSpan(
                          style: t(12, c: C.muted, h: 1.5),
                          children: [
                            const TextSpan(text: 'Questions? '),
                            WidgetSpan(
                              child: GestureDetector(
                                onTap: () => context.pushHelp(),
                                child: Text(
                                  'Contact support',
                                  style: t(12, w: FontWeight.w600, c: C.brand, deco: TextDecoration.underline),
                                ),
                              ),
                            ),
                            const TextSpan(text: ' · We are happy to help with anything about your bookings or data.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _refund(Json p) {
    final tiers = [
      (C.mint, C.green700, C.green900, const Color(0xFF166534)),
      (C.amberSoft, C.amber, const Color(0xFF713F12), C.amber),
      (C.orangeSoft, C.orange, C.orangeDeep, C.orangeInk),
    ];
    final rules = asList(p['refund_rules']);
    return [
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Refund when you cancel', size: 17),
            const SizedBox(height: 12),
            Text('Based on time left before your slot starts. Applies to slot charges.', style: t(13, c: C.muted)),
            const SizedBox(height: 12),
            for (var i = 0; i < rules.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: tiers[i.clamp(0, 2)].$1, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('${rules[i]['percent']}%', style: d(20, c: tiers[i.clamp(0, 2)].$2)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rules[i]['title'],
                            style: t(14, w: FontWeight.w700, c: tiers[i.clamp(0, 2)].$3),
                          ),
                          Text(rules[i]['subtitle'], style: t(12, c: tiers[i.clamp(0, 2)].$4)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const H2('Good to know', size: 17),
            const SizedBox(height: 12),
            for (final n in asList(p['refund_notes']))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (_noteColors[n['color']] ?? _noteColors['gray']!).$1,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _noteIcons[n['icon']] ?? LucideIcons.info,
                        size: 16,
                        color: (_noteColors[n['color']] ?? _noteColors['gray']!).$2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: t(13, c: C.mutedInk, h: 1.55),
                          children: [
                            TextSpan(
                              text: '${n['heading']}: ',
                              style: t(13, w: FontWeight.w700, h: 1.55),
                            ),
                            TextSpan(text: n['body']),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _privacy(List<Json> sections, bool privacy) => [
    if (privacy)
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: C.tealSoft, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Icon(LucideIcons.shieldCheck, color: C.teal, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: t(13, c: const Color(0xFF164E63), h: 1.5),
                  children: [
                    TextSpan(
                      text: 'No account, minimal data. ',
                      style: t(13, w: FontWeight.w700, c: const Color(0xFF164E63)),
                    ),
                    const TextSpan(text: "We only collect what's needed to confirm your booking and let the venue check you in."),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    for (final s in sections)
      CardBox(
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            H2(s['heading'], size: 16),
            const SizedBox(height: 8),
            for (final i in (s['items'] as List))
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: t(13, c: C.mutedInk, h: 1.7)),
                    Expanded(
                      child: Text('$i', style: t(13, c: C.mutedInk, h: 1.7)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
  ];
}
