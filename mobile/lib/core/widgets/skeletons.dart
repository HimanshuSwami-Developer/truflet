import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/theme.dart';
import 'buttons.dart';

/// Shimmering placeholders shown while a screen or section loads.
/// Each one mirrors the layout it stands in for (same cards, radii and spacing), so content
/// replaces it without the page jumping.

const _shimmer = ShimmerEffect(
  baseColor: Color(0xFFE3EAE0),
  highlightColor: Color(0xFFF5F8F3),
  duration: Duration(milliseconds: 1300),
);

/// Shimmer zone: every [Bone] inside animates; real containers draw as-is.
class Skeleton extends StatelessWidget {
  final Widget child;
  const Skeleton({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    container: true,
    child: ExcludeSemantics(
      child: Skeletonizer.zone(effect: _shimmer, child: child),
    ),
  );
}

// ---------------------------------------------------------------- building blocks

Widget _box(double? w, double h, [double r = 10]) => Bone(width: w, height: h, borderRadius: BorderRadius.circular(r));
Widget _text(int words, [double size = 14]) => Bone.text(words: words, fontSize: size);
Widget _pill([double w = 64]) => _box(w, 22, 999);
const _gap4 = SizedBox(height: 4), _gap8 = SizedBox(height: 8), _gap12 = SizedBox(height: 12);

BoxDecoration _card(double r, [List<BoxShadow>? shadow = shadowCard]) =>
    BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r), boxShadow: shadow);

/// Back button + a title line, for full-page skeletons of pushed screens.
Widget _header(double top, {bool translucent = false}) => Padding(
  padding: EdgeInsets.fromLTRB(20, top + 8, 20, 12),
  child: Row(
    children: [
      BackSquare(translucent: translucent),
      const SizedBox(width: 12),
      _text(2, 20),
    ],
  ),
);

// ---------------------------------------------------------------- lists & cards

/// Explore: venue cards (photo, name, area, price, sport pills).
class VenueCardsSkeleton extends StatelessWidget {
  final int count;
  const VenueCardsSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            decoration: _card(24),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _box(null, 170, 0),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [_text(3, 18), _gap4, _text(4, 13)],
                            ),
                          ),
                          _box(64, 34, 8),
                        ],
                      ),
                      _gap8,
                      Row(children: [_pill(70), const SizedBox(width: 6), _pill(84)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// My bookings: booking cards (thumbnail, venue, sport, date/time/paid strip).
class BookingCardsSkeleton extends StatelessWidget {
  final int count;
  const BookingCardsSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            decoration: _card(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(76, 76, 16),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [_text(3, 16), _gap8, _text(2, 13), _gap8, _pill(110)],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: const BoxDecoration(
                    color: C.ground,
                    border: Border(top: BorderSide(color: C.dashed)),
                  ),
                  child: Row(
                    children: [
                      for (var k = 0; k < 3; k++)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [_text(1, 11), _gap4, _text(2, 13)],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Rows of "icon/photo + title + subtitle" cards (notifications, games, groups, friends…).
class ListSkeleton extends StatelessWidget {
  final int count;
  final double leading;
  final bool circle;
  final EdgeInsets padding;
  const ListSkeleton({
    super.key,
    this.count = 5,
    this.leading = 40,
    this.circle = false,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 0),
  });

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: _card(18, shadowSoft),
              child: Row(
                children: [
                  circle ? Bone.circle(size: leading) : _box(leading, leading, leading * 0.3),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_text(3), _gap4, _text(6, 12)]),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Saved venues: two-column tiles.
class SavedGridSkeleton extends StatelessWidget {
  const SavedGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              decoration: _card(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _box(null, 120, 0),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_text(3), _gap4, _text(2, 12), _gap8, _pill()],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(children: [_text(1, 15), const Spacer(), _box(52, 34, 10)]),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Slot picker: the hourly grid inside the "Pick a start time" card.
class SlotGridSkeleton extends StatelessWidget {
  const SlotGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var g = 0; g < 2; g++) ...[
          _text(4, 13),
          _gap8,
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: [for (var i = 0; i < 4; i++) _box(null, double.infinity, 12)],
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}

/// Location picker: "Popular cities" grid and the areas list.
class CityAreaSkeleton extends StatelessWidget {
  const CityAreaSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        _text(2, 13),
        _gap12,
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [for (var i = 0; i < 6; i++) _box(null, double.infinity, 18)],
        ),
        const SizedBox(height: 24),
        _text(3, 13),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  height: 54,
                  decoration: i < 4
                      ? const BoxDecoration(
                          border: Border(bottom: BorderSide(color: C.divider)),
                        )
                      : null,
                  child: Row(
                    children: [
                      _box(18, 18, 6),
                      const SizedBox(width: 12),
                      Expanded(child: _text(2, 15)),
                      _text(2, 12),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Cards of headed text blocks (policies).
class TextCardsSkeleton extends StatelessWidget {
  const TextCardsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: _card(20, shadowSoft),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text(4, 17),
                  _gap12,
                  for (var k = 0; k < 3; k++) ...[_box(null, 52, 14), _gap8],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- full pages

/// Venue details: hero photo, title, facts, sports and amenities.
class VenueDetailsSkeleton extends StatelessWidget {
  const VenueDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Skeleton(
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 330,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _box(null, 330, 0),
                Positioned(top: top + 8, left: 20, child: const BackSquare(translucent: true)),
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
                  Row(children: [_pill(80), const SizedBox(width: 8), _pill(110)]),
                  _gap8,
                  _text(3, 26),
                  _gap8,
                  _text(6, 14),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: _box(null, 64, 16))],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _text(2, 18),
                  _gap12,
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: _box(null, 68, 18))],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _text(1, 18),
                  _gap12,
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: _box(null, 76, 16))],
                    ],
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

/// Ticket: venue banner, QR pass and booking details.
class TicketSkeleton extends StatelessWidget {
  const TicketSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Skeleton(
      child: ListView(
        padding: EdgeInsets.only(bottom: 32),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _header(top),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            decoration: _card(26, shadowBig),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _box(double.infinity, 120, 0),
                const SizedBox(height: 20),
                _box(196, 196, 18),
                _gap12,
                _text(1, 18),
                _gap8,
                _text(8, 12),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Column(
                    children: [
                      for (var r = 0; r < 3; r++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              for (var k = 0; k < 2; k++)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [_text(1, 11), _gap4, _text(2)],
                                  ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(child: _box(null, 50, 16)),
                const SizedBox(width: 10),
                Expanded(child: _box(null, 50, 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tournament / group pages: hero banner, stat tiles and a list of cards.
class HeroPageSkeleton extends StatelessWidget {
  final double heroHeight;
  final bool stats;
  const HeroPageSkeleton({super.key, this.heroHeight = 200, this.stats = true});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _box(null, heroHeight, 0),
                Positioned(top: top + 8, left: 20, child: const BackSquare(translucent: true)),
              ],
            ),
          ),
          if (stats)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: _box(null, 58, 16))],
                ],
              ),
            ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: _box(null, 50, 16)),
          const ListSkeleton(count: 4, leading: 44, padding: EdgeInsets.fromLTRB(20, 10, 20, 0)),
        ],
      ),
    );
  }
}

/// Profile tab: the white summary card and detail rows under the green header.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Container(
            height: top + 16 + 40 + 70,
            decoration: const BoxDecoration(
              color: C.brand,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -56),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: _card(24, shadowBig),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _box(72, 72, 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [_text(2, 20), _gap4, _text(3, 13), _gap4, _text(4, 12)],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [for (var i = 0; i < 4; i++) Expanded(child: Center(child: _box(40, 36, 8)))],
                      ),
                    ],
                  ),
                ),
                for (var c = 0; c < 2; c++)
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: _card(20, shadowSoft),
                    child: Column(
                      children: [
                        for (var r = 0; r < 3; r++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _box(36, 36, 10),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [_text(1, 11), _gap4, _text(3)],
                                  ),
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
        ],
      ),
    );
  }
}

/// Create wizard step 1 while sports load: type tiles, name field and sport grid.
class FormSkeleton extends StatelessWidget {
  const FormSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _box(null, 116, 18)),
              const SizedBox(width: 10),
              Expanded(child: _box(null, 116, 18)),
            ],
          ),
          const SizedBox(height: 18),
          _text(2, 13),
          _gap8,
          _box(null, 52, 14),
          const SizedBox(height: 18),
          _text(1, 13),
          _gap8,
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.15,
            children: [for (var i = 0; i < 6; i++) _box(null, double.infinity, 14)],
          ),
        ],
      ),
    ),
  );
}
