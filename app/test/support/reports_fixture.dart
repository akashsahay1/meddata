// Shared fixtures for the report tests: a server profit report and a
// signed-in Reports screen that is served it.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/presentation/screens/reports_screen.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/reports_api.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// GET /reports/profit as the server answers it (see ProfitReportApiTest).
Map<String, dynamic> sampleProfit() {
  Map<String, dynamic> bucket(int qty, int revenue, int costed, int cost,
          {int sales = 0, int unknownQty = 0, int unknownRevenue = 0}) =>
      <String, dynamic>{
        'qty_units': qty,
        'revenue_paise': revenue,
        'sales_paise': sales,
        'costed_revenue_paise': costed,
        'cost_paise': cost,
        'unknown_cost_qty_units': unknownQty,
        'unknown_cost_revenue_paise': unknownRevenue,
        'profit_paise': costed - cost,
        'margin_bp': costed == 0 ? null : ((costed - cost) * 10000 / costed).round(),
      };
  return <String, dynamic>{
    'from': '2026-10-01',
    'to': '2026-10-05',
    'totals': bucket(6, 37597, 32835, 25000,
        sales: 41375, unknownQty: 1, unknownRevenue: 4762)
      ..['bills'] = 3,
    'by_day': <Map<String, dynamic>>[
      bucket(2, 5714, 5714, 4000)..['date'] = '2026-10-03',
      bucket(4, 31883, 27121, 21000, unknownQty: 1, unknownRevenue: 4762)
        ..['date'] = '2026-10-05',
    ],
    'by_product': <Map<String, dynamic>>[
      bucket(3, 27121, 27121, 21000)
        ..addAll(<String, dynamic>{'product_id': 'p2', 'name': 'Cough Syrup', 'category': 'Cough & Cold'}),
      bucket(2, 5714, 5714, 4000)
        ..addAll(<String, dynamic>{'product_id': 'p1', 'name': 'Dolo 650', 'category': 'Pain Relief'}),
      bucket(1, 4762, 0, 0, unknownQty: 1, unknownRevenue: 4762)
        ..addAll(<String, dynamic>{'product_id': 'p3', 'name': 'Mystery Tonic', 'category': 'Tonics'}),
    ],
    'by_category': <Map<String, dynamic>>[
      bucket(3, 27121, 27121, 21000)..['category'] = 'Cough & Cold',
      bucket(2, 5714, 5714, 4000)..['category'] = 'Pain Relief',
      bucket(1, 4762, 0, 0, unknownQty: 1, unknownRevenue: 4762)..['category'] = 'Tonics',
    ],
    'unknown_cost': <Map<String, dynamic>>[
      <String, dynamic>{
        'product_id': 'p3', 'batch_id': 'b3', 'name': 'Mystery Tonic',
        'batch_no': 'MT1', 'qty_units': 1, 'revenue_paise': 4762,
      },
    ],
  };
}

/// The token in memory (platform secure storage has no test implementation).
class MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

/// An AuthService signed in with token "tok".
Future<AuthService> signedInAuth(TestApp app, ApiClient api) async {
  final SharedPreferences p = await SharedPreferences.getInstance();
  await p.setString('auth_token', 'tok');
  final AuthService auth =
      AuthService(app.settings, 'test-device', api, MemoryTokenStore());
  await auth.init();
  return auth;
}

/// A server that answers GET /reports/profit with [sampleProfit] (or
/// fails as offline when [online] is false). Requests go to [requests].
ApiClient profitServer({bool online = true, List<Uri>? requests}) =>
    ApiClient(MockClient((http.Request r) async {
      requests?.add(r.url);
      if (!online) throw http.ClientException('offline');
      return http.Response(jsonEncode(sampleProfit()), 200,
          headers: <String, String>{'content-type': 'application/json'});
    }));

/// [ReportsScreen] signed in, talking to [server].
Widget signedInReports(AuthService auth, ApiClient server, {int initialTab = 0}) =>
    ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: ReportsScreen(initialTab: initialTab, reportsApi: ReportsApi(server)),
    );
