import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/billing_repository.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/domain/fefo.dart';
import 'package:med_stock/presentation/screens/billing/new_bill_screen.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_api_test.dart' show sampleBill;

final DateTime _expiry = DateTime(2030, 12, 31);

class _Meds extends MedicineRepository {
  @override
  Future<List<Medicine>> getAll() async => <Medicine>[
        Medicine(
          id: 'B1',
          productId: 'P1',
          name: 'Dolo 650',
          brand: 'Micro Labs',
          batchNo: 'B1',
          quantity: 10,
          unit: 'Strips',
          sellingPrice: 30,
          expiryDate: _expiry,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
}

class _Batches extends BillingRepository {
  Map<String, int>? appliedStock;

  @override
  Future<List<SaleBatch>> batchesOf(String productId) async => <SaleBatch>[
        SaleBatch(
          id: 'B1',
          productId: 'P1',
          productName: 'Dolo 650',
          unit: 'Strips',
          batchNo: 'B1',
          expiryDate: _expiry,
          mrpPaise: 3000,
          version: 7,
          qty: 10,
          gstRateBp: 500,
        ),
      ];

  @override
  Future<void> applyServerStock(Map<String, int> qtyByBatch) async => appliedStock = qtyByBatch;
}

/// The server: GET /shops/current, then scripted answers to POST /bills.
class _Server extends ApiClient {
  bool online = false;
  final List<({int status, Map<String, dynamic>? body})> answers =
      <({int status, Map<String, dynamic>? body})>[];
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  @override
  Future<({int status, Map<String, dynamic>? body})> currentShop(String token) async => online
      ? (status: 200, body: <String, dynamic>{
          'shop': <String, dynamic>{
            'name': 'Sahay Medicals', 'gstin': '27AAPFU0939F1ZV', 'state_code': '27',
            'address': '12 Station Road', 'default_gst_rate_bp': 500,
          },
        })
      : (status: 0, body: null);

  @override
  Future<({int status, Map<String, dynamic>? body})> postResult(String path, Map<String, dynamic> body,
      {String? token, Duration? timeout}) async {
    sent.add(body);
    return answers.removeAt(0);
  }
}

void main() {
  testWidgets('counter sale: offline gate, FEFO line, stale price, bill made', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok', 'auth_email': 'a@b.c'});
    final AuthService auth = AuthService(SettingsService(), 'phone-1');
    await auth.init();
    final MedicineProvider meds = MedicineProvider(_Meds());
    await meds.load();
    final SyncEngine sync = SyncEngine(tokenProvider: () => null, userKeyProvider: () => null);
    final _Server server = _Server();
    final _Batches batches = _Batches();

    await tester.pumpWidget(MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<MedicineProvider>.value(value: meds),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NewBillScreen(api: BillingApi(server), repository: batches))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Offline: billing is blocked (inventory isn't).
    expect(find.text('Billing needs internet'), findsOneWidget);
    server.online = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Billing needs internet'), findsNothing);

    // Search, add, one more.
    await tester.enterText(find.byType(TextField).first, 'dolo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolo 650'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B1 · Exp 12/30 · MRP ₹30.00 × 1'), findsOneWidget);
    await tester.tap(find.byTooltip('One more'));
    await tester.pumpAndSettle();
    expect(find.text('₹60.00'), findsWidgets);

    // The server says the price changed: "₹30.00 is now ₹32.00".
    server.answers.add((status: 409, body: <String, dynamic>{
      'error': 'price_changed',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'batch_id': 'B1', 'name': 'Dolo 650', 'batch_no': 'B1',
          'sent_mrp_paise': 3000, 'mrp_paise': 3200, 'batch_version': 9, 'price_changed': true},
      ],
    }));
    await tester.tap(find.text('Create bill'));
    await tester.pumpAndSettle();
    expect(find.text('Dolo 650 (B1): ₹30.00 is now ₹32.00'), findsOneWidget);
    await tester.tap(find.text('Use new prices'));
    await tester.pumpAndSettle();
    expect(find.text('₹64.00'), findsWidgets);

    // Second try goes through with the accepted price and the same bill id.
    server.answers.add((status: 201, body: <String, dynamic>{
      'bill': sampleBill(),
      'batches': <Map<String, dynamic>>[<String, dynamic>{'batch_id': 'B1', 'qty_units': 8}],
      'replayed': false,
    }));
    await tester.tap(find.text('Create bill'));
    await tester.pumpAndSettle();

    expect(server.sent, hasLength(2));
    expect(server.sent[1]['id'], server.sent[0]['id']);
    expect(server.sent[0]['lines'], <Map<String, Object?>>[
      <String, Object?>{'batch_id': 'B1', 'qty_units': 2, 'mrp_paise': 3000, 'batch_version': 7, 'discount_bp': 0},
    ]);
    expect((server.sent[1]['lines'] as List<dynamic>).single,
        containsPair('mrp_paise', 3200));
    expect((server.sent[1]['lines'] as List<dynamic>).single, containsPair('batch_version', 9));
    expect(server.sent[1]['device_id'], 'phone-1');
    expect(batches.appliedStock, <String, int>{'B1': 8});

    // The bill opens on top of the counter screen.
    expect(find.text('Bill saved. Stock updated on all devices.'), findsOneWidget);
    expect(find.text('MED/26-27/000042'), findsWidgets);

    // "New bill": back to the counter screen, empty, for the next customer.
    await tester.tap(find.text('New bill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search or scan to add medicines'), findsOneWidget);
    expect(find.text('Dolo 650'), findsNothing);

    // Leaving an empty bill goes straight back to where billing started.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
