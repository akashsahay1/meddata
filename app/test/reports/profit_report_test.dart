import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/domain/reports/profit_report.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:med_stock/services/reports_api.dart';

import '../support/reports_fixture.dart';

void main() {
  test('ProfitReport reads the server report', () {
    final ProfitReport r = ProfitReport.fromJson(sampleProfit());
    expect(r.from, DateTime(2026, 10, 1));
    expect(r.to, DateTime(2026, 10, 5));
    expect(<int?>[r.totals.revenuePaise, r.totals.costPaise, r.totals.profitPaise,
        r.totals.marginBp, r.totals.bills, r.totals.salesPaise],
        <int?>[37597, 25000, 7835, 2386, 3, 41375]);
    expect(r.totals.hasUnknownCost, isTrue);
    expect(r.byDay.map((ProfitRow d) => d.key), <String>['2026-10-03', '2026-10-05']);
    expect(r.byProduct.map((ProfitRow p) => p.label),
        <String>['Cough Syrup', 'Dolo 650', 'Mystery Tonic']);
    expect(r.byProduct.last.marginBp, isNull);
    expect(r.byCategory.first.label, 'Cough & Cold');
    expect(r.unknownCost.single.batchNo, 'MT1');
    expect(r.isEmpty, isFalse);
  });

  test('margin text', () {
    expect(marginText(2386), '23.86%');
    expect(marginText(3000), '30.00%');
    expect(marginText(-505), '-5.05%');
    expect(marginText(null), '–');
  });

  group('ReportsApi.profit', () {
    test('asks for the date range and parses the report', () async {
      late Uri asked;
      final ReportsApi api = ReportsApi(ApiClient(MockClient((http.Request req) async {
        asked = req.url;
        expect(req.headers['Authorization'], 'Bearer tok');
        return http.Response(jsonEncode(sampleProfit()), 200);
      })));
      final ApiOutcome<ProfitReport> r =
          await api.profit('tok', from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 5));
      expect(asked.path, endsWith('/reports/profit'));
      expect(asked.queryParameters, <String, String>{'from': '2026-10-01', 'to': '2026-10-05'});
      expect(r.value!.totals.profitPaise, 7835);
    });

    test('offline and errors', () async {
      final ReportsApi offline = ReportsApi(ApiClient(MockClient(
          (http.Request req) async => throw http.ClientException('no network'))));
      final ApiOutcome<ProfitReport> o =
          await offline.profit('tok', from: DateTime(2026), to: DateTime(2026));
      expect(o.isOffline, isTrue);

      final ReportsApi tooLong = ReportsApi(ApiClient(MockClient((http.Request req) async =>
          http.Response(jsonEncode(<String, dynamic>{
            'message': 'Choose a range of at most 366 days.',
            'errors': <String, dynamic>{'to': <String>['Choose a range of at most 366 days.']},
          }), 422))));
      final ApiOutcome<ProfitReport> e =
          await tooLong.profit('tok', from: DateTime(2024), to: DateTime(2026));
      expect(<Object?>[e.isOk, e.status, e.message],
          <Object?>[false, 422, 'Choose a range of at most 366 days.']);
    });
  });
}
