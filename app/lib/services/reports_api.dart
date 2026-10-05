import '../domain/reports/profit_report.dart';
import 'api_client.dart';
import 'billing_api.dart';

/// Reports the server works out from its data (profit from bills).
class ReportsApi {
  ReportsApi([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// GET /reports/profit for [from]..[to] (inclusive dates).
  Future<ApiOutcome<ProfitReport>> profit(String token,
      {required DateTime from, required DateTime to}) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.getResult(
      '/reports/profit',
      token: token,
      query: <String, String>{
        'from': BillingApi.ymd(from),
        'to': BillingApi.ymd(to),
      },
      timeout: const Duration(seconds: 30),
    );
    if (r.status == 200 && r.body != null) {
      try {
        return ApiOutcome<ProfitReport>.ok(ProfitReport.fromJson(r.body!));
      } catch (_) {
        return const ApiOutcome<ProfitReport>.failed(
            200, 'The server sent a report this app could not read.');
      }
    }
    return ApiOutcome<ProfitReport>.failed(
        r.status, BillingApi.errorMessage(r.status, r.body));
  }
}
