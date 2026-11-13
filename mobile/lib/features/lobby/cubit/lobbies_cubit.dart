import '../../../app/router/app_routes.dart';
import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/lobby_repository.dart';

/// 3 · Open Lobbies: one slot at a venue, every lobby at a venue, or the city board.
class LobbiesCubit extends DataCubit<List<Json>> {
  LobbiesCubit({required LobbiesArgs args, required LobbyRepository repository, int? areaId})
    : super(() {
        final venue = args.venue;
        if (venue != null) {
          return repository.venueLobbies(
            venue['id'],
            date: args.date,
            startHour: args.startHour,
            courtId: args.courtId,
            sportId: args.sportId,
          );
        }
        final area = args.areaId ?? areaId;
        return area == null ? Future.value(<Json>[]) : repository.cityLobbies(area, sportId: args.sportId);
      });
}

/// Matches tab: `{upcoming, requests, past}`.
class MyMatchesCubit extends DataCubit<Json> {
  MyMatchesCubit({required LobbyRepository repository}) : super(repository.mine);
}
