import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_state.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/venue_repository.dart';
import '../../booking/open_slot_booking.dart';
import '../../shell/widgets/bottom_nav.dart';
import '../cubit/saved_cubit.dart';

/// 11 · Saved venues (in Profile)
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => SavedCubit(repository: c.read<VenueRepository>(), app: c.read<AppCubit>()),
    child: const _SavedView(),
  );
}

class _SavedView extends StatefulWidget {
  const _SavedView();
  @override
  State<_SavedView> createState() => _SavedViewState();
}

class _SavedViewState extends State<_SavedView> {
  SavedCubit get _cubit => context.read<SavedCubit>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final error = await _cubit.load();
    if (error != null && mounted) toast(context, error);
  }

  Future<void> _undo() async {
    final error = await _cubit.undo();
    if (error != null && mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<SavedCubit, SavedState>(builder: _build);

  Widget _build(BuildContext context, SavedState st) {
    final app = context.watch<AppCubit>();
    final s = app.state;
    final items = st.items, removed = st.removed;
    final alerts = s.user?['slot_alerts_on'] == true;
    final top = MediaQuery.of(context).padding.top;
    final n = items?.length ?? 0;
    return WithNav(
      current: AppTab.profile,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, top + 8, 0, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        const Icon(LucideIcons.chevronLeft, size: 16, color: C.brand),
                        Text(
                          'Profile',
                          style: t(13, w: FontWeight.w600, c: C.brand),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Saved venues', style: d(28, ls: -0.5)),
                const SizedBox(height: 4),
                Text('$n ${n == 1 ? 'venue' : 'venues'} · tap a heart to remove', style: t(13, c: C.muted)),
              ],
            ),
          ),
          if (items == null) const SavedGridSkeleton(),
          if (items != null && items.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.66,
                children: [for (final v in items) _tile(v)],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: C.purpleSoft, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/images/racket.jpg', width: 56, height: 56, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get slot alerts',
                          style: t(14, w: FontWeight.w700, c: const Color(0xFF4C1D95)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "We'll ping you when evening slots open up at your saved venues.",
                          style: t(12, c: const Color(0xFF5B21B6), h: 1.4),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    toggled: alerts,
                    label: 'Slot alerts',
                    child: GestureDetector(
                      onTap: () => app.updateMe({'slot_alerts_on': !alerts}),
                      child: Toggle(alerts, on: C.purple, off: const Color(0xFFC4B5FD)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (items != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: C.roseSoft, borderRadius: BorderRadius.circular(28)),
                    child: const Icon(Icons.favorite_border, color: C.rose, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text('No saved venues yet', style: d(20)),
                  const SizedBox(height: 12),
                  Text(
                    'Tap the heart on any turf to keep it here for quick booking.',
                    textAlign: TextAlign.center,
                    style: t(14, c: C.muted, h: 1.5),
                  ),
                  if (removed.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GhostButton('Undo', height: 44, radius: 14, onTap: _undo),
                  ],
                  const SizedBox(height: 12),
                  PrimaryButton(
                    'Explore turfs',
                    height: 52,
                    radius: 16,
                    fontSize: 15,
                    onTap: () => context.goTab(AppTab.explore),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(Json v) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: shadowCard),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final cubit = context.read<SavedCubit>();
                  await context.pushVenue(v['id']); // may unsave / book there
                  if (!cubit.isClosed) cubit.load();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 120,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Img(v['image']),
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                children: [
                                  const Icon(Icons.star_rounded, size: 12, color: C.star),
                                  const SizedBox(width: 3),
                                  Text('${v['rating']}', style: t(11, w: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v['name'], maxLines: 2, overflow: TextOverflow.ellipsis, style: d(14, h: 1.25)),
                          const SizedBox(height: 4),
                          Text(
                            '${v['area']}${v['distance_km'] != null ? ' · ${v['distance_km']} km' : ''}',
                            style: t(12, c: C.muted),
                          ),
                          const SizedBox(height: 4),
                          if (asList(v['sports']).isNotEmpty) SportPill(asList(v['sports']).first),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: inr(v['price_from']),
                            style: d(15, c: C.brand),
                          ),
                          TextSpan(
                            text: '/hr',
                            style: t(12, c: C.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 34,
                    child: Material(
                      color: C.brand,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final cubit = context.read<SavedCubit>();
                          await openSlotBooking(context, v['id']);
                          if (!cubit.isClosed) cubit.load();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            child: Text(
                              'Book',
                              style: t(12, w: FontWeight.w600, c: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Semantics(
            button: true,
            label: 'Remove ${v['name']} from saved',
            child: GestureDetector(
              onTap: () => _cubit.remove(v),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle),
                child: const Icon(Icons.favorite, size: 17, color: C.rose),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
