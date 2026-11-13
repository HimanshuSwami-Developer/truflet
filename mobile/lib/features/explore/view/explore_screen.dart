import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/router/app_routes.dart';
import '../../../app/session/app_cubit.dart';
import '../../../app/session/app_state.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/lobby_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/venue_repository.dart';
import '../../auth/auth_guard.dart';
import '../cubit/explore_cubit.dart';
import '../cubit/explore_state.dart';

/// 1 · Home / Discovery
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => ExploreCubit(
      venues: c.read<VenueRepository>(),
      notifications: c.read<NotificationRepository>(),
      lobbies: c.read<LobbyRepository>(),
      app: c.read<AppCubit>(),
    )..load(),
    child: const _ExploreView(),
  );
}

class _ExploreView extends StatelessWidget {
  const _ExploreView();

  Future<void> _toggleFav(BuildContext context, Json v) async {
    if (!await requireLogin(context)) return;
    if (!context.mounted) return;
    final error = await context.read<ExploreCubit>().toggleFavourite(v);
    if (error != null && context.mounted) toast(context, error);
  }

  void _filters(BuildContext context) {
    final cubit = context.read<ExploreCubit>();
    var f = cubit.state.filters;
    sheet(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final sort = cubit.state.sort;
          final amenities = cubit.state.amenities;
          final lo = (f.priceMin ?? priceFloor).toDouble(), hi = (f.priceMax ?? priceCeiling).toDouble();
          void update(ExploreFilters next) => set(() => f = next);
          Widget chip(String label, bool on, VoidCallback onTap) => Choice(
            selected: on,
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onTap: onTap,
            child: Text(label, style: t(13, w: FontWeight.w600, c: on ? Colors.white : C.ink)),
          );
          final today = DateTime.now();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Sort & filter', style: d(22))),
                  if (f.count > 0)
                    GestureDetector(
                      onTap: () => update(const ExploreFilters()),
                      child: Text('Clear all', style: t(13, w: FontWeight.w700, c: C.brand)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Sort by', style: t(13, w: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final k in exploreSortOrder) ...[
                    Expanded(
                      child: Choice(
                        selected: sort == k,
                        onTap: () {
                          cubit.setSort(k);
                          set(() {});
                        },
                        child: Text(
                          exploreSortLabels[k]!,
                          style: t(13, w: FontWeight.w700, c: sort == k ? Colors.white : C.ink),
                        ),
                      ),
                    ),
                    if (k != 'rating') const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Text('Free slot on', style: t(13, w: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      chip(
                        i == 0 ? 'Today' : i == 1 ? 'Tomorrow' : DateFormat('EEE d').format(today.add(Duration(days: i))),
                        f.dayOffset == i,
                        () => update(f.copyWith(dayOffset: f.dayOffset == i ? null : i)),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, w) in timeWindows.indexed)
                    chip(
                      '${w.$1} · ${fmtHour(w.$2)}–${fmtHour(w.$3)}',
                      f.window == i,
                      () => update(f.copyWith(window: f.window == i ? null : i)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Text('Price per hour', style: t(13, w: FontWeight.w600))),
                  Text(
                    '${inr(lo)} – ${hi >= priceCeiling ? '${inr(priceCeiling)}+' : inr(hi)}',
                    style: t(13, w: FontWeight.w700, c: C.brand),
                  ),
                ],
              ),
              RangeSlider(
                values: RangeValues(lo, hi),
                min: priceFloor.toDouble(),
                max: priceCeiling.toDouble(),
                divisions: 30,
                activeColor: C.brand,
                inactiveColor: C.segment,
                onChanged: (v) => update(
                  f.copyWith(
                    priceMin: v.start <= priceFloor ? null : v.start.round(),
                    priceMax: v.end >= priceCeiling ? null : v.end.round(),
                  ),
                ),
              ),
              if (amenities.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Amenities', style: t(13, w: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in amenities)
                      chip(
                        a['name'],
                        f.amenities.contains(a['icon']),
                        () => update(
                          f.copyWith(
                            amenities: f.amenities.contains(a['icon'])
                                ? ({...f.amenities}..remove(a['icon']))
                                : {...f.amenities, a['icon'] as String},
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                'Show results',
                onTap: () {
                  Navigator.pop(ctx);
                  cubit.setFilters(f);
                  cubit.load();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ExploreCubit, ExploreState>(builder: _build);

  Widget _build(BuildContext context, ExploreState st) {
    final cubit = context.read<ExploreCubit>();
    final s = context.watch<AppCubit>().state;
    final venues = st.venues, error = st.error, unread = st.unread, sort = st.sort;
    final offer = asMap(s.config['offer']);
    final top = MediaQuery.of(context).padding.top;
    return RefreshIndicator(
      color: C.brand,
      onRefresh: cubit.load,
      child: ListView(
        padding: EdgeInsets.only(top: top + 8, bottom: 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final changed = await context.pushLocation();
                      if (changed == true) cubit.load();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Playing in', style: t(12, c: C.muted)),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: C.brand),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${s.areaName}${s.cityName.isNotEmpty ? ', ${s.cityName}' : ''}',
                                overflow: TextOverflow.ellipsis,
                                style: t(16, w: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(LucideIcons.chevronDown, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Stack(
                  children: [
                    SquareIconButton(
                      LucideIcons.bell,
                      label: 'Notifications',
                      onTap: () async {
                        if (!await requireLogin(context)) return;
                        if (!context.mounted) return;
                        await context.pushNotifications();
                        cubit.clearUnread();
                      },
                    ),
                    if (unread > 0)
                      Positioned(
                        top: 10,
                        right: 11,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA580C),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Ready for your\nnext game?', style: d(26, h: 1.15, ls: -0.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: C.line),
                      boxShadow: shadowSoft,
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.search, size: 18, color: C.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            style: t(15),
                            textInputAction: TextInputAction.search,
                            onChanged: cubit.searchChanged,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Search turfs, courts, venues',
                              hintStyle: t(15, c: C.muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: 'More filters',
                  child: GestureDetector(
                    onTap: () => _filters(context),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: C.brand,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: shadowBrandSm,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(LucideIcons.slidersHorizontal, color: Colors.white, size: 20),
                          if (st.filters.count > 0)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                width: 16,
                                height: 16,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
                                child: Text('${st.filters.count}', style: t(10, w: FontWeight.w700)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 12), child: H2('Choose your sport')),
          SizedBox(
            height: 98,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _chip(context, st, null, 'All', null, C.brand),
                for (final sp in s.sports) _chip(context, st, sp['id'], sp['name'], sp['image'], hex(sp['fg'])),
              ],
            ),
          ),
          if (offer['enabled'] == true) _offer(offer),
          if (st.cityLobbies.isNotEmpty) ..._cityBoard(context, st.cityLobbies, s),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      H2(venues == null ? 'Arenas near you' : '${venues.length} arena${venues.length == 1 ? '' : 's'} near you'),
                      if (st.radiusLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(LucideIcons.radar, size: 13, color: C.green700),
                            const SizedBox(width: 4),
                            Text(st.radiusLabel, style: t(12, w: FontWeight.w600, c: C.green700)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: cubit.cycleSort,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: C.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.arrowUpDown, size: 14, color: C.brand),
                        const SizedBox(width: 4),
                        Text(exploreSortLabels[sort]!, style: t(12, w: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (st.notice.isNotEmpty && venues != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.blueSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(LucideIcons.locateFixed, size: 16, color: C.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(st.notice, style: t(13, c: C.blueInk))),
                ],
              ),
            ),
          if (st.filters.count > 0 && venues != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text('${st.filters.count} filter${st.filters.count == 1 ? '' : 's'} on', style: t(13, c: C.muted)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: cubit.clearFilters,
                    child: Text('Clear', style: t(13, w: FontWeight.w700, c: C.brand)),
                  ),
                ],
              ),
            ),
          if (error != null) ErrorRetry(error, onRetry: cubit.load),
          if (venues == null && error == null) const VenueCardsSkeleton(),
          if (venues != null && venues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No arenas match. Try another sport, time or fewer filters.',
                textAlign: TextAlign.center,
                style: t(14, c: C.muted),
              ),
            ),
          for (final v in venues ?? <Json>[])
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: _card(context, v, s)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ExploreState st, int? id, String label, String? img, Color fg) {
    final on = st.sportId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: () => context.read<ExploreCubit>().selectSport(id),
          child: SizedBox(
            width: 72,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: on ? fg : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: on ? null : Border.all(color: C.line),
                    boxShadow: on ? const [BoxShadow(color: Color(0x2E10231A), blurRadius: 18, offset: Offset(0, 8))] : null,
                  ),
                  child: img == null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset('assets/images/turf.jpg', fit: BoxFit.cover),
                        )
                      : Img(img, radius: BorderRadius.circular(18)),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: t(12, w: on ? FontWeight.w700 : FontWeight.w500, c: on ? fg : C.ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The city board: public lobbies with open spots.
  List<Widget> _cityBoard(BuildContext context, List<Json> lobbies, AppState s) {
    void openBoard() => context.pushLobbies(LobbiesArgs(areaId: s.areaId, cityName: s.cityName));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Row(
          children: [
            Expanded(child: H2('Open lobbies in ${s.cityName}')),
            GestureDetector(
              onTap: openBoard,
              child: Text('See all', style: t(13, w: FontWeight.w700, c: C.brand)),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: lobbies.length.clamp(0, 8),
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final g = lobbies[i];
            final locked = g['slot_state'] == 'turf_locked';
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: openBoard,
                child: Container(
                  width: 236,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SportPill(asMap(g['sport'])),
                          const SizedBox(width: 6),
                          Pill(
                            locked ? 'Turf locked' : 'Crowdfunding',
                            bg: locked ? C.mint : C.amberSoft,
                            fg: locked ? C.green700 : C.amber,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          ),
                          const Spacer(),
                          Text(
                            (g['per_head'] ?? 0) > 0 ? inr(g['per_head']) : 'Free',
                            style: t(12, w: FontWeight.w700, c: C.brand),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${g['date_label']} · ${g['time_label']}', style: t(14, w: FontWeight.w700)),
                      Text(
                        '${g['venue']?['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t(12, c: C.muted),
                      ),
                      const Spacer(),
                      Text(
                        '${g['spots_left']} spot${g['spots_left'] == 1 ? '' : 's'} left · ${g['taken']}/${g['capacity']} in',
                        style: t(12, w: FontWeight.w600, c: C.green700),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _offer(Json o) => Container(
    margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    constraints: const BoxConstraints(minHeight: 128),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(child: Img(o['image'], fallback: 'stumps')),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xE00A2816), Color(0x8C0A2816), Color(0x000A2816)], stops: [0, 0.55, 1]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Pill(o['tag'] ?? '', bg: C.lime, fg: C.ink),
                const SizedBox(height: 6),
                Text(o['title'] ?? '', style: d(20, c: Colors.white, h: 1.15)),
                const SizedBox(height: 6),
                Text(o['subtitle'] ?? '', style: t(12, c: C.limeSoft)),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _card(BuildContext context, Json v, AppState s) {
    final fav = s.saved.contains(v['id']);
    final km = v['distance_km'];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: shadowCard),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => context.pushVenue(v['id']),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 170,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Img(v['image']),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.5, 1],
                              colors: [Colors.transparent, Color(0x80000000)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Row(
                            children: [
                              if (v['is_fast_filling'] == true) ...[
                                const Pill('Fast filling', bg: C.lime, fg: C.ink),
                                const SizedBox(width: 6),
                              ],
                              if ((v['open_lobbies'] ?? 0) > 0)
                                Pill(
                                  '${v['open_lobbies']} open ${v['open_lobbies'] == 1 ? 'lobby' : 'lobbies'}',
                                  bg: Colors.white,
                                  fg: C.green700,
                                ),
                            ],
                          ),
                        ),
                        if (km != null)
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '${(km as num).toStringAsFixed(1)} km',
                                  style: t(12, w: FontWeight.w600, c: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 14, color: C.star),
                                const SizedBox(width: 3),
                                Text('${v['rating']}', style: t(12, w: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v['name'], style: d(18, h: 1.2)),
                                  const SizedBox(height: 2),
                                  Text('${v['area']} · ${_count(v['review_count'])} reviews', style: t(13, c: C.muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('from', style: t(12, c: C.muted, h: 1.2)),
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: inr(v['price_from']),
                                        style: d(18, c: C.brand),
                                      ),
                                      TextSpan(
                                        text: '/hr',
                                        style: t(12, c: C.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final sp in asList(v['sports'])) SportPill(sp, size: 12),
                            if ((v['highlight'] ?? '').toString().isNotEmpty)
                              Pill(
                                v['highlight'],
                                bg: C.chip,
                                fg: C.muted,
                                size: 12,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Semantics(
              button: true,
              label: fav ? 'Remove from favourites' : 'Save to favourites',
              child: GestureDetector(
                onTap: () => _toggleFav(context, v),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle),
                  child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 19, color: C.rose),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _count(dynamic n) {
  final v = (n ?? 0) as int;
  return v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';
}
