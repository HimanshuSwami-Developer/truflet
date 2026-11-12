import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell.dart';

/// 3 · Choose location
class LocationScreen extends StatefulWidget {
  final bool first;
  const LocationScreen({super.key, this.first = false});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  List<Json> cities = [];
  int city = 0;
  int? areaId;
  String query = '';
  bool gpsBusy = false;
  String? gpsLabel;
  double? lat, lng;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = context.read<AppState>();
      final data = asList(await api.get('/cities/'));
      var ci = 0;
      for (var i = 0; i < data.length; i++) {
        if (asList(data[i]['areas']).any((a) => a['id'] == s.areaId)) ci = i;
      }
      setState(() {
        cities = data;
        city = ci;
        areaId = s.areaId ?? (data.isNotEmpty && asList(data[ci]['areas']).isNotEmpty ? asList(data[ci]['areas']).first['id'] : null);
        error = null;
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  List<Json> get areas => cities.isEmpty ? [] : asList(cities[city]['areas']);
  Json? get area => areas.where((a) => a['id'] == areaId).firstOrNull;

  Future<void> _useGps() async {
    setState(() => gpsBusy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw ApiError('Location permission is off. Pick your area below.');
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      final r = asMap(await api.get('/locate/', {'lat': pos.latitude, 'lng': pos.longitude}));
      final ci = cities.indexWhere((c) => c['id'] == r['city_id']);
      setState(() {
        if (ci >= 0) city = ci;
        areaId = r['area_id'];
        lat = pos.latitude;
        lng = pos.longitude;
        gpsLabel = 'Located: ${r['area']}, ${r['city']}';
      });
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => gpsBusy = false);
    }
  }

  Future<void> _continue() async {
    final a = area;
    if (a == null) return;
    await context.read<AppState>().setArea(
        id: a['id'], area: a['name'], city: cities[city]['name'], lat: lat ?? a['lat']?.toDouble(), lng: lng ?? a['lng']?.toDouble());
    if (!mounted) return;
    if (widget.first) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final filteredAreas = query.isEmpty
        ? areas
        : cities
            .expand((c) => asList(c['areas']).map((a) => {...a, '_city': c['name']}))
            .where((a) => '${a['name']} ${a['pincode']} ${a['_city']}'.toLowerCase().contains(query.toLowerCase()))
            .toList();
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            SizedBox(
              height: 210,
              child: Stack(fit: StackFit.expand, children: [
                Image.asset('assets/images/turf.jpg', fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.45, 1],
                      colors: [Color(0x40000000), Color(0x00F5F8F3), C.ground],
                    ),
                  ),
                ),
                Positioned(top: top + 8, left: 20, child: BackSquare(translucent: true, onTap: () => Navigator.of(context).maybePop())),
              ]),
            ),
            Transform.translate(
              offset: const Offset(0, -36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Where do you play?', style: d(28, ls: -0.5)),
                  const SizedBox(height: 6),
                  Text("We'll show turfs and courts near you.", style: t(15, c: C.muted)),
                  const SizedBox(height: 18),
                  _searchBox(),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 52,
                    child: Material(
                      color: C.mint,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: gpsBusy ? null : _useGps,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          gpsBusy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.green700))
                              : const Icon(LucideIcons.locateFixed, size: 20, color: C.green700),
                          const SizedBox(width: 8),
                          Text(gpsLabel ?? 'Use my current location', style: t(15, w: FontWeight.w600, c: C.green700)),
                        ]),
                      ),
                    ),
                  ),
                  if (error != null) ErrorRetry(error!, onRetry: _load),
                  if (cities.isNotEmpty && query.isEmpty) ...[
                    const Label('Popular cities', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.25,
                      children: [
                        for (var i = 0; i < cities.length; i++) _cityTile(i),
                      ],
                    ),
                  ],
                  Label(query.isEmpty ? 'Areas in ${cities.isEmpty ? '' : cities[city]['name']}' : 'Matching areas',
                      padding: const EdgeInsets.fromLTRB(0, 24, 0, 6)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.line)),
                    child: Column(children: [
                      for (var i = 0; i < filteredAreas.length; i++) _areaRow(filteredAreas[i], i < filteredAreas.length - 1),
                      if (filteredAreas.isEmpty)
                        Padding(padding: const EdgeInsets.all(16), child: Text('No areas match "$query"', style: t(14, c: C.muted))),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + MediaQuery.of(context).padding.bottom / 2),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: C.line))),
          child: PrimaryButton('Show turfs in ${area?['name'] ?? '…'}', onTap: area == null ? null : _continue),
        ),
      ]),
    );
  }

  Widget _searchBox() => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line), boxShadow: shadowSoft),
        child: Row(children: [
          const Icon(LucideIcons.search, size: 20, color: C.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => query = v.trim()),
              style: t(15),
              decoration: InputDecoration(
                  border: InputBorder.none, hintText: 'Search area, locality or pincode', hintStyle: t(15, c: C.muted), isDense: true),
            ),
          ),
        ]),
      );

  Widget _cityTile(int i) {
    final on = i == city;
    return Semantics(
      selected: on,
      button: true,
      child: GestureDetector(
        onTap: () => setState(() {
          city = i;
          final a = asList(cities[i]['areas']);
          areaId = a.isNotEmpty ? a.first['id'] : null;
          gpsLabel = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: on ? C.brand : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? C.brand : C.line),
            boxShadow: on ? shadowBrandSm : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.building2, size: 22, color: on ? Colors.white : C.ink),
            const SizedBox(height: 6),
            Text(cities[i]['name'], style: t(13, w: FontWeight.w600, c: on ? Colors.white : C.ink)),
          ]),
        ),
      ),
    );
  }

  Widget _areaRow(Json a, bool border) {
    final on = a['id'] == areaId;
    return InkWell(
      onTap: () => setState(() {
        areaId = a['id'];
        if (a['_city'] != null) city = cities.indexWhere((c) => c['name'] == a['_city']);
        query = '';
        FocusScope.of(context).unfocus();
      }),
      child: Container(
        height: 54,
        decoration: border ? const BoxDecoration(border: Border(bottom: BorderSide(color: C.divider))) : null,
        child: Row(children: [
          const Icon(LucideIcons.mapPin, size: 18, color: C.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(a['_city'] != null ? '${a['name']}, ${a['_city']}' : a['name'], style: t(15))),
          Text('${a['venue_count']} venues', style: t(12, c: C.muted)),
          if (on) ...[const SizedBox(width: 12), const Icon(LucideIcons.check, size: 20, color: C.brand)],
        ]),
      ),
    );
  }
}
