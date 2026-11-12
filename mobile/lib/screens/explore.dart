import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'details.dart';
import 'location.dart';
import 'notifications.dart';

/// 4 · Turf listing + filters
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

const _sortOrder = ['near', 'price', 'rating'];
const _sortLabels = {'near': 'Nearest', 'price': 'Lowest price', 'rating': 'Top rated'};

class _ExploreScreenState extends State<ExploreScreen> {
  int? sportId;
  String sort = 'near';
  String q = '';
  List<Json>? venues;
  String? error;
  int unread = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      await s.ensureBasics();
      final data = asList(await api.get('/venues/', {
        if (s.areaId != null) 'area': s.areaId,
        if (sportId != null) 'sport': sportId,
        if (q.isNotEmpty) 'q': q,
        if (s.lat != null) 'lat': s.lat,
        if (s.lng != null) 'lng': s.lng,
        'sort': sort,
      }));
      s.saved
        ..clear()
        ..addAll(data.where((v) => v['is_saved'] == true).map((v) => v['id'] as int));
      setState(() {
        venues = data;
        error = null;
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
    if (s.loggedIn) {
      try {
        final n = asMap(await api.get('/notifications/'));
        if (mounted) setState(() => unread = n['unread'] ?? 0);
      } catch (_) {}
    }
  }

  Future<void> _toggleFav(Json v) async {
    final s = context.read<AppState>();
    if (!await requireLogin(context)) return;
    final id = v['id'] as int;
    setState(() => s.saved.contains(id) ? s.saved.remove(id) : s.saved.add(id));
    try {
      final r = asMap(await api.post('/venues/$id/save/'));
      setState(() => r['is_saved'] == true ? s.saved.add(id) : s.saved.remove(id));
    } catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  void _filters() {
    sheet(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Sort & filter', style: d(22)),
        const SizedBox(height: 14),
        Text('Sort by', style: t(13, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          for (final k in _sortOrder) ...[
            Expanded(
              child: Choice(
                selected: sort == k,
                onTap: () {
                  set(() {});
                  setState(() => sort = k);
                },
                child: Text(_sortLabels[k]!, style: t(13, w: FontWeight.w700, c: sort == k ? Colors.white : C.ink)),
              ),
            ),
            if (k != 'rating') const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 20),
        PrimaryButton('Show results', onTap: () {
          Navigator.pop(ctx);
          _load();
        }),
      ]);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final offer = asMap(s.config['offer']);
    final top = MediaQuery.of(context).padding.top;
    return RefreshIndicator(
      color: C.brand,
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.only(top: top + 8, bottom: 20), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final changed = await push<bool>(context, const LocationScreen());
                  if (changed == true) _load();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Playing in', style: t(12, c: C.muted)),
                  Row(children: [
                    const Icon(Icons.location_on, size: 16, color: C.brand),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('${s.areaName}${s.cityName.isNotEmpty ? ', ${s.cityName}' : ''}',
                          overflow: TextOverflow.ellipsis, style: t(16, w: FontWeight.w700)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.chevronDown, size: 16),
                  ]),
                ]),
              ),
            ),
            Stack(children: [
              SquareIconButton(LucideIcons.bell, label: 'Notifications', onTap: () async {
                if (!await requireLogin(context)) return;
                if (!context.mounted) return;
                await push(context, const NotificationsScreen());
                setState(() => unread = 0);
              }),
              if (unread > 0)
                Positioned(
                  top: 10,
                  right: 11,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEA580C), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text('Ready for your\nnext game?', style: d(26, h: 1.15, ls: -0.5)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line), boxShadow: shadowSoft),
                child: Row(children: [
                  const Icon(LucideIcons.search, size: 18, color: C.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      style: t(15),
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () {
                          q = v.trim();
                          _load();
                        });
                      },
                      decoration: InputDecoration(
                          border: InputBorder.none, isDense: true, hintText: 'Search turfs, courts, venues', hintStyle: t(15, c: C.muted)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'More filters',
              child: GestureDetector(
                onTap: _filters,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(16), boxShadow: shadowBrandSm),
                  child: const Icon(LucideIcons.slidersHorizontal, color: Colors.white, size: 20),
                ),
              ),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(20, 22, 20, 12), child: H2('Choose your sport')),
        SizedBox(
          height: 98,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            _chip(null, 'All', null, C.brand),
            for (final sp in s.sports) _chip(sp['id'], sp['name'], sp['image'], hex(sp['fg'])),
          ]),
        ),
        if (offer['enabled'] == true) _offer(offer),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Row(children: [
            Expanded(child: H2(venues == null ? 'Venues near you' : '${venues!.length} venues near you')),
            GestureDetector(
              onTap: () {
                setState(() => sort = _sortOrder[(_sortOrder.indexOf(sort) + 1) % 3]);
                _load();
              },
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.line)),
                child: Row(children: [
                  const Icon(LucideIcons.arrowUpDown, size: 14, color: C.brand),
                  const SizedBox(width: 4),
                  Text(_sortLabels[sort]!, style: t(12, w: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        if (error != null) ErrorRetry(error!, onRetry: _load),
        if (venues == null && error == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: C.brand))),
        if (venues != null && venues!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('No venues match. Try another sport or area.', textAlign: TextAlign.center, style: t(14, c: C.muted)),
          ),
        for (final v in venues ?? <Json>[]) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: _card(v, s)),
      ]),
    );
  }

  Widget _chip(int? id, String label, String? img, Color fg) {
    final on = sportId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          onTap: () {
            setState(() => sportId = id);
            _load();
          },
          child: SizedBox(
            width: 72,
            child: Column(children: [
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
                    ? ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/turf.jpg', fit: BoxFit.cover))
                    : Img(img, radius: BorderRadius.circular(18)),
              ),
              const SizedBox(height: 6),
              Text(label, style: t(12, w: on ? FontWeight.w700 : FontWeight.w500, c: on ? fg : C.ink)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _offer(Json o) => Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        constraints: const BoxConstraints(minHeight: 128),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            Positioned.fill(child: Img(o['image'], fallback: 'stumps')),
            const Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xE00A2816), Color(0x8C0A2816), Color(0x000A2816)], stops: [0, 0.55, 1]),
              ),
            )),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Pill(o['tag'] ?? '', bg: C.lime, fg: C.ink),
                const SizedBox(height: 6),
                Text(o['title'] ?? '', style: d(20, c: Colors.white, h: 1.15)),
                const SizedBox(height: 6),
                Text(o['subtitle'] ?? '', style: t(12, c: C.limeSoft)),
              ]),
            ),
          ]),
        ),
      );

  Widget _card(Json v, AppState s) {
    final fav = s.saved.contains(v['id']);
    final km = v['distance_km'];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: shadowCard),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Material(
          color: Colors.white,
          child: InkWell(
            onTap: () async {
              await push(context, DetailsScreen(venueId: v['id']));
              setState(() {});
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                height: 170,
                child: Stack(fit: StackFit.expand, children: [
                  Img(v['image']),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.5, 1], colors: [Colors.transparent, Color(0x80000000)]),
                    ),
                  ),
                  if (v['is_fast_filling'] == true) const Positioned(left: 12, top: 12, child: Pill('Fast filling', bg: C.lime, fg: C.ink)),
                  if (km != null)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Row(children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('${(km as num).toStringAsFixed(1)} km', style: t(12, w: FontWeight.w600, c: Colors.white)),
                      ]),
                    ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.star_rounded, size: 14, color: C.star),
                        const SizedBox(width: 3),
                        Text('${v['rating']}', style: t(12, w: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v['name'], style: d(18, h: 1.2)),
                        const SizedBox(height: 2),
                        Text('${v['area']} · ${_count(v['review_count'])} reviews', style: t(13, c: C.muted)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('from', style: t(12, c: C.muted, h: 1.2)),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: inr(v['price_from']), style: d(18, c: C.brand)),
                        TextSpan(text: '/hr', style: t(12, c: C.muted)),
                      ])),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final sp in asList(v['sports'])) SportPill(sp, size: 12),
                    if ((v['highlight'] ?? '').toString().isNotEmpty)
                      Pill(v['highlight'], bg: C.chip, fg: C.muted, size: 12, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Semantics(
            button: true,
            label: fav ? 'Remove from favourites' : 'Save to favourites',
            child: GestureDetector(
              onTap: () => _toggleFav(v),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle),
                child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 19, color: C.rose),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

String _count(dynamic n) {
  final v = (n ?? 0) as int;
  return v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v';
}
