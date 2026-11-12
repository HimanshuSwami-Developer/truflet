import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/external_actions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/venue_repository.dart';
import '../../auth/auth_guard.dart';
import '../../community/widgets/play_mode_sheet.dart';
import '../cubit/venue_details_cubit.dart';

const amenityIcons = {
  'parking': LucideIcons.squareParking,
  'floodlights': LucideIcons.lightbulb,
  'washroom': LucideIcons.bath,
  'water': LucideIcons.droplet,
  'changing': LucideIcons.shirt,
  'equipment': LucideIcons.dumbbell,
  'wifi': LucideIcons.wifi,
  'cafe': LucideIcons.coffee,
  'first_aid': LucideIcons.cross,
  'seating': LucideIcons.armchair,
};

/// 5 · Turf details
class VenueDetailsScreen extends StatelessWidget {
  final int venueId;
  const VenueDetailsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => VenueDetailsCubit(venueId: venueId, repository: c.read<VenueRepository>(), app: c.read<AppCubit>())..load(),
    child: const _VenueDetailsView(),
  );
}

class _VenueDetailsView extends StatefulWidget {
  const _VenueDetailsView();
  @override
  State<_VenueDetailsView> createState() => _VenueDetailsViewState();
}

/// Photo and sport selection are view-only state.
class _VenueDetailsViewState extends State<_VenueDetailsView> {
  int photo = 0;
  int sportIdx = 0;

  Future<void> _fav(Json v) async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    final error = await context.read<VenueDetailsCubit>().toggleFavourite(v);
    if (error != null && mounted) toast(context, error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DataBuilder<VenueDetailsCubit, Json>(skeleton: const VenueDetailsSkeleton(), builder: (context, v) => _body(v)),
    );
  }

  Widget _body(Json v) {
    final s = context.watch<AppCubit>().state;
    final photos = (v['photos'] as List).cast<String?>();
    final sports = asList(v['venue_sports']);
    final cur = sports.isEmpty ? null : sports[sportIdx.clamp(0, sports.length - 1)];
    final fav = s.saved.contains(v['id']);
    final top = MediaQuery.of(context).padding.top;
    final hero = photos.isEmpty ? v['image'] : photos[photo.clamp(0, photos.length - 1)];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 330,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Img(hero, key: ValueKey(hero)),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0, 0.35, 0.6, 1],
                          colors: [Color(0x59000000), Colors.transparent, Colors.transparent, Color(0x73000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: top + 8,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          const BackSquare(translucent: true),
                          const Spacer(),
                          SquareIconButton(
                            LucideIcons.share2,
                            translucent: true,
                            iconSize: 18,
                            label: 'Share',
                            onTap: () {
                              SharePlus.instance.share(ShareParams(text: '${v['name']} on Turflet — ${v['address']}'));
                            },
                          ),
                          const SizedBox(width: 10),
                          Semantics(
                            button: true,
                            label: 'Save to favourites',
                            child: GestureDetector(
                              onTap: () => _fav(v),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 18, color: C.rose),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (photos.length > 1)
                      Positioned(
                        left: 20,
                        bottom: 44,
                        child: Row(
                          children: [
                            for (var i = 0; i < photos.length && i < 5; i++)
                              GestureDetector(
                                onTap: () => setState(() => photo = i),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 52,
                                  height: 52,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: i == photo ? Colors.white : Colors.white.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Img(photos[i], radius: BorderRadius.circular(10)),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Container(
                  decoration: const BoxDecoration(
                    color: C.ground,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          if (v['is_fast_filling'] == true) const Pill('Fast filling', bg: C.lime, fg: C.ink),
                          Pill('Open · ${v['hours_label']}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(v['name'], style: d(26, h: 1.15, ls: -0.4)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 16, color: C.star),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text.rich(
                              TextSpan(
                                style: t(14, c: C.muted),
                                children: [
                                  TextSpan(
                                    text: '${v['rating']}',
                                    style: t(14, w: FontWeight.w700),
                                  ),
                                  TextSpan(
                                    text:
                                        ' (${v['review_count']} reviews) · ${v['area']}'
                                        '${v['distance_km'] != null ? ' · ${v['distance_km']} km' : ''}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: _fact('Surface', v['surface'])),
                          const SizedBox(width: 10),
                          Expanded(child: _fact('Size', v['size'])),
                          const SizedBox(width: 10),
                          Expanded(child: _fact('Courts', '${v['court_count']} courts')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const H2('Sports available'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var i = 0; i < sports.length && i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(child: _sportTile(sports[i], i == sportIdx, () => setState(() => sportIdx = i))),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                      const H2('Amenities'),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.35,
                        children: [for (final a in asList(v['amenities'])) _amenity(a)],
                      ),
                      if ((v['about'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const H2('About'),
                        const SizedBox(height: 8),
                        Text(v['about'], style: t(14, c: C.muted, h: 1.6)),
                      ],
                      if ((v['rules'] as List).isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: C.orangeBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: C.orangeSoft),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const H2('Venue rules', size: 16, color: C.orangeInk),
                              const SizedBox(height: 8),
                              for (final r in v['rules'])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('•  ', style: t(14, c: C.orangeDeep, h: 1.7)),
                                      Expanded(
                                        child: Text(r, style: t(14, c: C.orangeDeep, h: 1.7)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const H2('Location'),
                      const SizedBox(height: 10),
                      CardBox(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                              child: SizedBox(
                                height: 120,
                                child: CustomPaint(
                                  painter: _MapGrid(),
                                  child: const Center(child: Icon(Icons.location_on, size: 40, color: C.brand)),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(v['address'] ?? '', style: t(13, c: C.muted, h: 1.4)),
                                  ),
                                  const SizedBox(width: 12),
                                  GhostButton(
                                    'Directions',
                                    height: 40,
                                    radius: 12,
                                    bg: C.mint,
                                    fg: C.green700,
                                    border: Colors.transparent,
                                    fontSize: 13,
                                    onTap: () => openMaps(v['lat'], v['lng'], '${v['name']} ${v['address']}'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: C.line)),
          ),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${cur?['name'] ?? ''} from', style: t(12, c: C.muted)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: inr(cur?['price'] ?? v['price_from']), style: d(24)),
                        TextSpan(
                          text: ' /hr',
                          style: t(13, c: C.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: PrimaryButton(
                      'Book a slot',
                      trailing: const Icon(LucideIcons.arrowRight, color: Colors.white, size: 18),
                      onTap: cur == null ? null : () => choosePlayMode(context, venue: v, sportId: cur['sport_id']),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fact(String k, String? v) => CardBox(
    padding: const EdgeInsets.all(12),
    radius: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: t(11, c: C.muted)),
        const SizedBox(height: 2),
        Text(v ?? '—', style: t(14, w: FontWeight.w600), maxLines: 2),
      ],
    ),
  );

  Widget _sportTile(Json sp, bool on, VoidCallback onTap) {
    final fg = hex(sp['fg']);
    return Semantics(
      selected: on,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? hex(sp['bg']) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? fg : C.line, width: 2),
          ),
          child: Row(
            children: [
              Img(sp['image'], width: 44, height: 44, radius: BorderRadius.circular(12)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sp['name'],
                      style: t(15, w: FontWeight.w700, c: on ? fg : C.ink),
                    ),
                    Text(
                      sp['meta'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(12, c: (on ? fg : C.ink).withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amenity(Json a) => CardBox(
    padding: EdgeInsets.zero,
    radius: 16,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: hex(a['bg']), borderRadius: BorderRadius.circular(10)),
          child: Icon(amenityIcons[a['icon']] ?? LucideIcons.check, size: 18, color: hex(a['fg'])),
        ),
        const SizedBox(height: 6),
        Text(a['name'], style: t(12, w: FontWeight.w500)),
      ],
    ),
  );
}

class _MapGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE8F0E4));
    final p = Paint()
      ..color = const Color(0xFFD7E2D2)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
