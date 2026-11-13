import '../../../core/network/json.dart';

const exploreSortOrder = ['near', 'price', 'rating'];
const exploreSortLabels = {'near': 'Nearest', 'price': 'Lowest price', 'rating': 'Top rated'};

/// Time windows offered in the filter sheet: (label, from hour, to hour exclusive).
const timeWindows = [('Morning', 6, 12), ('Afternoon', 12, 16), ('Evening', 16, 20), ('Night', 20, 24)];

/// Hourly price slider bounds (₹).
const priceFloor = 0, priceCeiling = 3000;

/// The filter bottom-sheet's choices. `null` = any.
class ExploreFilters {
  final Set<String> amenities; // amenity icon keys
  final int? priceMin, priceMax;
  final int? dayOffset; // 0 = today
  final int? window; // index into [timeWindows]
  const ExploreFilters({this.amenities = const {}, this.priceMin, this.priceMax, this.dayOffset, this.window});

  int get count =>
      amenities.length + (priceMin != null || priceMax != null ? 1 : 0) + (dayOffset != null || window != null ? 1 : 0);

  static const _keep = Object();

  ExploreFilters copyWith({
    Set<String>? amenities,
    Object? priceMin = _keep,
    Object? priceMax = _keep,
    Object? dayOffset = _keep,
    Object? window = _keep,
  }) => ExploreFilters(
    amenities: amenities ?? this.amenities,
    priceMin: identical(priceMin, _keep) ? this.priceMin : priceMin as int?,
    priceMax: identical(priceMax, _keep) ? this.priceMax : priceMax as int?,
    dayOffset: identical(dayOffset, _keep) ? this.dayOffset : dayOffset as int?,
    window: identical(window, _keep) ? this.window : window as int?,
  );
}

class ExploreState {
  /// null until the first load finishes.
  final List<Json>? venues;
  final String? error;
  final int unread;
  final int? sportId;
  final String sort;
  final String q;
  final ExploreFilters filters;

  /// "Within 5 km" / "City-wide" — the auto-expanding radius badge.
  final String radiusLabel;

  /// Non-empty when the radius was widened ("Expanded search to 10 km to show more arenas").
  final String notice;

  /// Public lobbies with open spots in my city (the board).
  final List<Json> cityLobbies;

  /// Amenity catalogue for the filter sheet.
  final List<Json> amenities;

  const ExploreState({
    this.venues,
    this.error,
    this.unread = 0,
    this.sportId,
    this.sort = 'near',
    this.q = '',
    this.filters = const ExploreFilters(),
    this.radiusLabel = '',
    this.notice = '',
    this.cityLobbies = const [],
    this.amenities = const [],
  });

  static const _keep = Object();

  ExploreState copyWith({
    Object? venues = _keep,
    Object? error = _keep,
    int? unread,
    Object? sportId = _keep,
    String? sort,
    String? q,
    ExploreFilters? filters,
    String? radiusLabel,
    String? notice,
    List<Json>? cityLobbies,
    List<Json>? amenities,
  }) => ExploreState(
    venues: identical(venues, _keep) ? this.venues : venues as List<Json>?,
    error: identical(error, _keep) ? this.error : error as String?,
    unread: unread ?? this.unread,
    sportId: identical(sportId, _keep) ? this.sportId : sportId as int?,
    sort: sort ?? this.sort,
    q: q ?? this.q,
    filters: filters ?? this.filters,
    radiusLabel: radiusLabel ?? this.radiusLabel,
    notice: notice ?? this.notice,
    cityLobbies: cityLobbies ?? this.cityLobbies,
    amenities: amenities ?? this.amenities,
  );
}
