import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// FAQs, support tickets and the policy pages.
class SupportRepository {
  final ApiClient _api;
  SupportRepository(this._api);

  Future<List<Json>> faqs(String q) async => asList(await _api.get('/faqs/', {if (q.isNotEmpty) 'q': q}));

  Future<void> createTicket({required String subject, required String message, dynamic bookingId}) =>
      _api.post('/support/tickets/', {'subject': subject, 'message': message, 'booking': ?bookingId});

  Future<Json> policies() async => asMap(await _api.get('/policies/'));
}
