import '../../../app/session/app_cubit.dart';
import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/venue_repository.dart';

/// 5 · Venue details: loads one venue and toggles it as a favourite.
class VenueDetailsCubit extends DataCubit<Json> {
  final VenueRepository _repo;
  final AppCubit _app;

  VenueDetailsCubit({required int venueId, required VenueRepository repository, required this._app})
    : _repo = repository,
      super(() => repository.details(venueId));

  /// Returns an error message, or null.
  Future<String?> toggleFavourite(Json v) async {
    try {
      final r = await _repo.toggleSaved(v['id']);
      _app.markSaved(v['id'], r['is_saved'] == true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
