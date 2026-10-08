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
  _Meds({this.unit = 'Strips', this.packSize = 1, this.qty = 10});
  final String unit;
  final int packSize;
  final int qty;

  @override
  Future<List<Medicine>> getAll() async => <Medicine>[
        Medicine(
          id: 'B1',
          productId: 'P1',
          name: 'Dolo 650',
          brand: 'Micro Labs',
          batchNo: 'B1',
          quantity: qty,
          unit: unit,
          packSize: packSize,
          sellingPrice: 30,
          expiryDate: _expiry,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
}

class _Batches extends BillingRepository {
  _Batches({this.unit = 'Strips', this.packSize = 1, this.qty = 10});
  final String unit;
  final int packSize;
  final int qty;
  Map<String, int>? appliedStock;

  @override
  Future<List<SaleBatch>> batchesOf(String productId) async => <SaleBatch>[
        SaleBatch(
          id: 'B1',
          productId: 'P1',
          productName: 'Dolo 650',
          unit: unit,
          packSize: packSize,
          batchNo: 'B1',
          expiryDate: _expiry,
          mrpPaise: 3000,
          version: 7,
          qty: qty,
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

/// The token in memory: the real store is platform secure storage, which has
/// no implementation under `flutter test` (a read would never complete).
class _MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  testWidgets('counter sale: offline gate, FEFO line, stale price, bill made', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok', 'auth_email': 'a@b.c'});
    final AuthService auth =
        AuthService(SettingsService(), 'phone-1', null, _MemoryTokenStore());
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
  testWidgets('strips + loose quantity: + 1 strip, the dialog, and closing it cleanly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok', 'auth_email': 'a@b.c'});
    final AuthService auth =
        AuthService(SettingsService(), 'phone-1', null, _MemoryTokenStore());
    await auth.init();
    // Dolo 650 counted in tablets, a strip of 15, priced ₹30 a strip.
    final MedicineProvider meds = MedicineProvider(_Meds(unit: 'Tablets', packSize: 15, qty: 100));
    await meds.load();
    final SyncEngine sync = SyncEngine(tokenProvider: () => null, userKeyProvider: () => null);
    final _Server server = _Server()..online = true;
    final _Batches batches = _Batches(unit: 'Tablets', packSize: 15, qty: 100);

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

    await tester.enterText(find.byType(TextField).first, 'dolo');
    await tester.pumpAndSettle();
    expect(find.textContaining('100 Tablets (6 strips + 10 tablets) · MRP ₹30.00/strip'), findsOneWidget);
    await tester.tap(find.text('Dolo 650'));
    await tester.pumpAndSettle();
    expect(find.text('= 1 tablet'), findsOneWidget);
    expect(find.textContaining('MRP ₹30.00/strip × 1'), findsOneWidget);

    await tester.tap(find.text('+ 1 strip'));
    await tester.pumpAndSettle();
    expect(find.text('= 1 strip + 1 tablet'), findsOneWidget);
    expect(find.text('₹32.00'), findsWidgets, reason: '16 tablets at ₹30 a strip of 15, rounded once');

    // The quantity box opens the strips + loose dialog.
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    expect(find.text('Quantity · 1 strip = 15 tablets'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Strips'), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Loose tablets'), '3');
    await tester.pump();
    expect(find.text('= 33 tablets'), findsOneWidget);
    await tester.tap(find.text('OK'));
    // Runs the dialog's exit animation: its fields must not touch disposed
    // controllers (they did, when disposal happened at pop).
    await tester.pumpAndSettle();
    expect(find.text('= 2 strips + 3 tablets'), findsOneWidget);
    expect(find.textContaining('× 33'), findsOneWidget);
    expect(find.text('₹66.00'), findsWidgets, reason: '33 x 30 / 15');

    // Cancel leaves the quantity alone; an empty dialog refuses OK.
    await tester.tap(find.text('33'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Strips'), '');
    await tester.enterText(find.widgetWithText(TextField, 'Loose tablets'), '');
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('Enter 1 or more'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('= 2 strips + 3 tablets'), findsOneWidget);
  });
}
