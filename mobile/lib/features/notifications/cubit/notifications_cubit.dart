import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/notification_repository.dart';

/// Loads the inbox and marks everything read in the background.
class NotificationsCubit extends DataCubit<Json> {
  NotificationsCubit({required NotificationRepository repository})
    : super(() async {
        final r = await repository.list();
        repository.markAllRead().ignore();
        return r;
      });
}
