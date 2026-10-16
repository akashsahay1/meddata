// Editing a bill in place: the bill screen's menu opens the counter screen
// filled from the bill; saving sends the edit and shows the saved bill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:medikabiz/data/repositories/billing_repository.dart';
import 'package:medikabiz/domain/fefo.dart';
import 'package:medikabiz/presentation/screens/billing/bill_detail_screen.dart';
import 'package:medikabiz/services/billing_api.dart';

import '../billing_api_test.dart' show sampleBill;
import '../support/accounting_fake.dart';
import '../support/test_app.dart';

/// The device's inventory: Dolo 650 batch b1 with 10 strips left.
class _Batches extends BillingRepository {
  Map<String, int>? applied;

  @override
  Future<List<SaleBatch>> batchesOf(String productId) async => <SaleBatch>[
        if (productId == 'p1')
          SaleBatch(
            id: 'b1', productId: 'p1', productName: 'Dolo 650', unit: 'Strips', batchNo: 'B1',
            expiryDate: DateTime(2030, 10, 31), mrpPaise: 3000, version: 7, qty: 10, gstRateBp: 500,
          ),
      ];

  @override
  Future<void> applyServerStock(Map<String, int> qtyByBatch) async => applied = qtyByBatch;
}

/// A cash bill of 2 strips of Dolo 650 (₹60).
Map<String, Object?> doloBill({int qty = 2, String? editedAt}) => <String, Object?>{
      ...sampleBill(),
      'id': 'b-1',
      'invoice_no': 'MED/26-27/000042',
      'payment_mode': 'cash',
      'customer_name': 'Alok',
      'customer_phone': '9650645839',
      'customer_gstin': null,
      'customer_state_code': null,
      'is_inter_state': false,
      'total_paise': 3000 * qty,
      'edited_at': editedAt,
      'items': <Object?>[
        <String, Object?>{
          'id': 1, 'line_no': 1, 'product_id': 'p1', 'batch_id': 'b1', 'name': 'Dolo 650', 'unit': 'Strips',
          'batch_no': 'B1', 'expiry_date': '2030-10-31', 'qty_units': qty, 'mrp_paise': 3000, 'discount_bp': 0,
          'gst_rate_bp': 500, 'total_paise': 3000 * qty,
        },
      ],
      'tax_summary': <Object?>[],
    };

void main() {
  testWidgets('Edit bill: filled from the bill, saved in place, back on the bill', (WidgetTester tester) async {
    usePhoneScreen(tester, height: 2400);
    final AccountsApp app = await AccountsApp.create();
    addTearDown(app.dispose);
    final _Batches batches = _Batches();
    app.server.billDetail = doloBill();
    app.server.editAnswer = doloBill(qty: 3, editedAt: '2026-10-06T04:45:00Z');
    app.server.editStock = <Object?>[<String, Object?>{'batch_id': 'b1', 'qty_units': 9}];

    await app.open(
        tester,
        BillDetailScreen(
            billId: 'b-1',
            api: BillingApi(app.server.client),
            accountingApi: app.server.api,
            repository: batches));
    expect(find.textContaining('Edited'), findsNothing);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel bill'), findsOneWidget);
    expect(find.text('Delete bill'), findsNothing, reason: 'bills are never deleted (gap-free numbers)');
    await tester.tap(find.text('Edit bill'));
    await tester.pumpAndSettle();

    // The counter screen, filled from the bill.
    expect(find.text('Edit MED/26-27/000042'), findsOneWidget);
    expect(find.text('Dolo 650'), findsWidgets);
    expect(find.text('Save changes'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Name')).controller!.text, 'Alok');

    // One more strip, then save.
    await tester.tap(find.byTooltip('One more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> sent = app.server.bodyOf('PATCH /bills/b-1')!;
    expect(sent.containsKey('id'), isFalse);
    expect(<Object?>[sent['payment_mode'], sent['customer_name'], sent['customer_phone']], <Object?>['cash', 'Alok', '9650645839']);
    expect(sent['lines'], <Object?>[
      <String, Object?>{'batch_id': 'b1', 'qty_units': 3, 'mrp_paise': 3000, 'batch_version': 7, 'discount_bp': 0},
    ]);
    expect(batches.applied, <String, int>{'b1': 9});

    // Back on the bill: same number, new total, the edit noted.
    expect(find.text('MED/26-27/000042'), findsWidgets);
    expect(find.text('₹90.00'), findsWidgets);
    final String when = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.utc(2026, 10, 6, 4, 45).toLocal());
    expect(find.text('Edited $when'), findsOneWidget);
  });
}
