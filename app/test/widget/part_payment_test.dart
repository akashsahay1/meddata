// Part-paid bills: what the bill and the bills list show, "Mark as paid",
// and the Pending filter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/billing/bill_detail_screen.dart';
import 'package:medikabiz/presentation/screens/billing/bills_screen.dart';
import 'package:medikabiz/services/billing_api.dart';

import '../billing_api_test.dart' show sampleBill;
import '../support/accounting_fake.dart';
import '../support/test_app.dart';

/// Ramesh's bill b-1: ₹1,600 total, ₹500 paid at the counter, ₹1,100 due.
Map<String, Object?> partPaid({int paid = 50000, int balance = 110000}) => <String, Object?>{
      ...sampleBill(),
      'id': 'b-1',
      'invoice_no': 'MED/26-27/000001',
      'payment_mode': 'credit',
      'party_id': 'p-ramesh',
      'customer_name': 'Ramesh Kumar',
      'total_paise': 160000,
      'paid_paise': paid,
      'balance_paise': balance,
      'received_paise': 50000,
      'received_mode': 'cash',
    };

void main() {
  Future<AccountsApp> start(WidgetTester tester) async {
    usePhoneScreen(tester, height: 2400);
    final AccountsApp app = await AccountsApp.create();
    addTearDown(app.dispose);
    return app;
  }

  testWidgets('a part-paid bill shows what is due; Mark as paid records the rest', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    app.server.billDetail = partPaid();
    await app.open(
        tester,
        BillDetailScreen(
            billId: 'b-1', api: BillingApi(app.server.client), accountingApi: app.server.api));

    expect(find.text('Part paid · ₹1,100.00 due'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('₹500.00'), findsOneWidget);
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('₹1,100.00'), findsOneWidget);

    await tester.tap(find.text('Mark as paid'));
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    final TextField amount = tester.widget<TextField>(find.widgetWithText(TextField, 'Amount (₹)'));
    expect(amount.controller!.text, '1100.00', reason: 'the balance is filled in');

    // Paid in full now; the bill reloads as paid.
    app.server.billDetail = partPaid(paid: 160000, balance: 0);
    await tester.tap(find.text('UPI'));
    await tester.tap(find.text('Save payment'));
    await tester.pumpAndSettle();
    final Map<String, dynamic> sent = app.server.bodyOf('POST /payments')!;
    expect(<Object?>[sent['party_id'], sent['bill_id'], sent['amount_paise'], sent['mode'], sent['direction']],
        <Object?>['p-ramesh', 'b-1', 110000, 'upi', 'in']);
    expect(find.text('Paid'), findsWidgets);
    expect(find.text('Part paid · ₹1,100.00 due'), findsNothing);
    expect(find.text('Mark as paid'), findsNothing);
  });

  testWidgets('a credit bill with nothing paid says so; the menu offers Mark as paid', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    app.server.billDetail = partPaid(paid: 0, balance: 160000);
    await app.open(
        tester, BillDetailScreen(billId: 'b-1', api: BillingApi(app.server.client), accountingApi: app.server.api));
    expect(find.text('Credit - to be paid'), findsOneWidget);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as paid'), findsWidgets);
  });

  testWidgets('bills list: balance due card, Due pill and the Pending filter', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    app.server.billList = <String, Object?>{
      'data': <Object?>[
        <String, Object?>{...partPaid(), 'items_count': 2},
        <String, Object?>{...sampleBill(), 'id': 'b-2', 'items_count': 1, 'paid_paise': 36400, 'balance_paise': 0},
      ],
      'meta': <String, Object?>{'current_page': 1, 'last_page': 1},
      'summary': <String, Object?>{'count': 2, 'total_paise': 196400, 'cancelled_count': 0, 'due_count': 1, 'due_paise': 110000},
    };
    await app.open(tester, BillsScreen(api: BillingApi(app.server.client)));

    expect(find.text('Due ₹1,100.00'), findsOneWidget);
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('1 bill to be paid'), findsOneWidget);
    expect(app.server.bodyOf('GET /bills')!.containsKey('due'), isFalse);

    await tester.ensureVisible(find.text('Pending'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pending'));
    await tester.pumpAndSettle();
    final Map<String, dynamic> q = app.server.bodyOf('GET /bills')!;
    expect(q['due'], '1');
    expect(q.containsKey('from'), isFalse, reason: 'pending bills of any date');
  });
}
