import '../../../core/bloc/data_cubit.dart';
import '../../../core/network/json.dart';
import '../../../data/repositories/support_repository.dart';

/// Refund rules, privacy and terms (managed from the admin panel).
class PolicyCubit extends DataCubit<Json> {
  PolicyCubit({required SupportRepository repository}) : super(repository.policies);
}
