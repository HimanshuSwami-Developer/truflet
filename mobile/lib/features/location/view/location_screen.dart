import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/location_repository.dart';
import '../cubit/location_cubit.dart';
import '../cubit/location_state.dart';

/// 3 · Choose location. [first] = part of onboarding: continuing opens home instead of popping back.
class LocationScreen extends StatelessWidget {
  final bool first;
  const LocationScreen({super.key, this.first = false});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => LocationCubit(repository: c.read<LocationRepository>(), app: c.read<AppCubit>())..load(),
    child: _LocationView(first: first),
  );
}

class _LocationView extends StatelessWidget {
  final bool first;
  const _LocationView({required this.first});

  Future<void> _useGps(BuildContext context) async {
    final error = await context.read<LocationCubit>().useGps();
    if (error != null && context.mounted) toast(context, error);
  }

  Future<void> _continue(BuildContext context) async {
    if (!await context.read<LocationCubit>().confirm()) return;
    if (!context.mounted) return;
    if (first) {
      context.goHome();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<LocationCubit, LocationState>(builder: _build);

  Widget _build(BuildContext context, LocationState st) {
    final cubit = context.read<LocationCubit>();
    final top = MediaQuery.of(context).padding.top;
    final cities = st.cities, city = st.city, query = st.query, area = st.area;
    final filteredAreas = st.filteredAreas;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: 210,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
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
                      Positioned(
                        top: top + 8,
                        left: 20,
                        child: BackSquare(translucent: true, onTap: () => Navigator.of(context).maybePop()),
                      ),
                    ],
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Where do you play?', style: d(28, ls: -0.5)),
                        const SizedBox(height: 6),
                        Text("We'll show turfs and courts near you.", style: t(15, c: C.muted)),
                        const SizedBox(height: 18),
                        _searchBox(cubit),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: Material(
                            color: C.mint,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: st.gpsBusy ? null : () => _useGps(context),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  st.gpsBusy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: C.green700),
                                        )
                                      : const Icon(LucideIcons.locateFixed, size: 20, color: C.green700),
                                  const SizedBox(width: 8),
                                  Text(
                                    st.gpsLabel ?? 'Use my current location',
                                    style: t(15, w: FontWeight.w600, c: C.green700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (st.error != null) ErrorRetry(st.error!, onRetry: cubit.load),
                        if (cities.isNotEmpty && query.isEmpty) ...[
                          const Label('Popular cities', padding: EdgeInsets.fromLTRB(0, 22, 0, 12)),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.25,
                            children: [for (var i = 0; i < cities.length; i++) _cityTile(cubit, st, i)],
                          ),
                        ],
                        Label(
                          query.isEmpty ? 'Areas in ${cities.isEmpty ? '' : cities[city]['name']}' : 'Matching areas',
                          padding: const EdgeInsets.fromLTRB(0, 24, 0, 6),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: C.line),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < filteredAreas.length; i++)
                                _areaRow(context, st, filteredAreas[i], i < filteredAreas.length - 1),
                              if (filteredAreas.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text('No areas match "$query"', style: t(14, c: C.muted)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + MediaQuery.of(context).padding.bottom / 2),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: C.line)),
            ),
            child: PrimaryButton('Show turfs in ${area?['name'] ?? '…'}', onTap: area == null ? null : () => _continue(context)),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(LocationCubit cubit) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: C.line),
      boxShadow: shadowSoft,
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.search, size: 20, color: C.muted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            onChanged: (v) => cubit.setQuery(v.trim()),
            style: t(15),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Search area, locality or pincode',
              hintStyle: t(15, c: C.muted),
              isDense: true,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _cityTile(LocationCubit cubit, LocationState st, int i) {
    final cities = st.cities;
    final on = i == st.city;
    final live = LocationState.isLive(cities[i]);
    return Semantics(
      selected: on,
      button: live,
      enabled: live,
      label: live ? null : '${cities[i]['name']}, coming soon',
      child: GestureDetector(
        onTap: live ? () => cubit.selectCity(i) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: on ? C.brand : (live ? Colors.white : C.chip),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? C.brand : C.line),
            boxShadow: on ? shadowBrandSm : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.building2, size: 22, color: on ? Colors.white : (live ? C.ink : C.radioOff)),
              const SizedBox(height: 6),
              Text(
                cities[i]['name'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t(13, w: FontWeight.w600, c: on ? Colors.white : (live ? C.ink : C.muted)),
              ),
              if (!live)
                Text(
                  'Coming soon',
                  style: t(10, w: FontWeight.w600, c: C.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _areaRow(BuildContext context, LocationState st, Json a, bool border) {
    final on = a['id'] == st.areaId;
    final live = a['_live'] != false;
    return InkWell(
      onTap: live
          ? () {
              context.read<LocationCubit>().selectArea(a);
              FocusScope.of(context).unfocus();
            }
          : null,
      child: Container(
        height: 54,
        decoration: border
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: C.divider)),
              )
            : null,
        child: Row(
          children: [
            const Icon(LucideIcons.mapPin, size: 18, color: C.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a['_city'] != null ? '${a['name']}, ${a['_city']}' : a['name'],
                style: t(15, c: live ? C.ink : C.muted),
              ),
            ),
            live
                ? Text('${a['venue_count']} venues', style: t(12, c: C.muted))
                : const Pill('Coming soon', bg: C.chip, fg: C.muted, padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
            if (on) ...[const SizedBox(width: 12), const Icon(LucideIcons.check, size: 20, color: C.brand)],
          ],
        ),
      ),
    );
  }
}
