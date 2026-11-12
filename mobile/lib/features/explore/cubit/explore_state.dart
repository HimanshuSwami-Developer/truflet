import '../../../core/network/json.dart';

const exploreSortOrder = ['near', 'price', 'rating'];
const exploreSortLabels = {'near': 'Nearest', 'price': 'Lowest price', 'rating': 'Top rated'};

class ExploreState {
  /// null until the first load finishes.
  final List<Json>? venues;
  final String? error;
  final int unread;
  final int? sportId;
  final String sort;
  final String q;

  /// Published games with open spots in my city (the public board).
  final List<Json> cityGames;

  const ExploreState({
    this.venues,
    this.error,
    this.unread = 0,
    this.sportId,
    this.sort = 'near',
    this.q = '',
    this.cityGames = const [],
  });

  static const _keep = Object();

  ExploreState copyWith({
    Object? venues = _keep,
    Object? error = _keep,
    int? unread,
    Object? sportId = _keep,
    String? sort,
    String? q,
    List<Json>? cityGames,
  }) => ExploreState(
    venues: identical(venues, _keep) ? this.venues : venues as List<Json>?,
    error: identical(error, _keep) ? this.error : error as String?,
    unread: unread ?? this.unread,
    sportId: identical(sportId, _keep) ? this.sportId : sportId as int?,
    sort: sort ?? this.sort,
    q: q ?? this.q,
    cityGames: cityGames ?? this.cityGames,
  );
}
