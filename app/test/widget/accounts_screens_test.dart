// Widget tests for the accounts screens (parties, ledger, payments,
// returns, purchases, GST reports) and the invoice scan's purchase entry,
// against a fake accounting server.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/bill.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/billing_repository.dart';
import 'package:med_stock/presentation/screens/billing/new_bill_screen.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:uuid/uuid.dart';
import 'package:med_stock/presentation/screens/accounts/gst_reports_screen.dart';
import 'package:med_stock/presentation/screens/accounts/note_detail_screen.dart';
import 'package:med_stock/presentation/screens/accounts/parties_screen.dart';
import 'package:med_stock/presentation/screens/accounts/party_detail_screen.dart';
import 'package:med_stock/presentation/screens/accounts/party_form_screen.dart';
import 'package:med_stock/presentation/screens/accounts/purchase_detail_screen.dart';
import 'package:med_stock/presentation/screens/accounts/purchases_screen.dart';
import 'package:med_stock/presentation/screens/accounts/return_screen.dart';
import 'package:med_stock/presentation/screens/invoice_scan_screen.dart';
import 'package:med_stock/services/invoice_scan_service.dart';

import '../support/accounting_fake.dart';
import '../support/test_app.dart' show loadAppFont, usePhoneScreen;

Bill _bill({String payment = 'cash', String? partyId}) => Bill.fromJson(<String, dynamic>{
      'id': 'b-1',
      'invoice_no': 'MED/26-27/000001',
      'bill_date': '2026-10-01',
      'status': 'final',
      'payment_mode': payment,
      'party_id': partyId,
      'customer_name': 'Ramesh Kumar',
      'is_inter_state': false,
      'seller': <String, dynamic>{'name': 'Sahay Medicals', 'gstin': '27AAPFU0939F1ZV'},
      'total_paise': 33600,
      'items': <Object>[
        <String, dynamic>{
          'id': 7, 'line_no': 1, 'product_id': 'P1', 'batch_id': 'B1', 'name': 'Dolo 650', 'batch_no': 'B1',
          'qty_units': 3, 'mrp_paise': 11200, 'discount_bp': 0, 'gst_rate_bp': 1200, 'taxable_paise': 30000,
          'cgst_paise': 1800, 'sgst_paise': 1800, 'igst_paise': 0, 'total_paise': 33600, 'returned_qty': 1,
        },
      ],
    });

void main() {
  setUpAll(loadAppFont);

  Future<AccountsApp> start(WidgetTester tester, {double height = 1600}) async {
    usePhoneScreen(tester, height: height);
    final AccountsApp app = await AccountsApp.create();
    addTearDown(app.dispose);
    return app;
  }

  testWidgets('parties: balances in words, filter and search', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, PartiesScreen(api: app.server.api));

    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('₹1,200.00 to collect'), findsOneWidget);
    expect(find.text('₹5,600.00 to pay'), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);
    // Totals of the list.
    expect(find.text('₹1,200.00'), findsOneWidget);
    expect(find.text('₹5,600.00'), findsOneWidget);

    await tester.tap(find.text('Suppliers'));
    await tester.pumpAndSettle();
    expect(app.server.requests.last.$2?['type'], 'supplier');
    expect(find.text('Ramesh Kumar'), findsNothing);
    expect(find.text('Asha Clinic'), findsOneWidget, reason: '"both" is a supplier too');

    await tester.enterText(find.byType(TextField), 'pune');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Pune Pharma Distributors'), findsOneWidget);
    expect(find.text('Asha Clinic'), findsNothing);
  });

  testWidgets('new party: GSTIN checked, state shown, opening balance owed by the shop',
      (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, PartyFormScreen(api: app.server.api));

    await tester.tap(find.text('Supplier'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Bengaluru Pharma');
    await tester.enterText(find.widgetWithText(TextFormField, 'GSTIN (optional)'), '29aabcu9603r1zx');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Not a valid GSTIN - check it'), findsOneWidget);
    expect(app.server.paths, isNot(contains('POST /parties')));

    await tester.enterText(find.widgetWithText(TextFormField, 'GSTIN (optional)'), '29AABCU9603R1ZJ');
    await tester.pump();
    expect(find.text('State: 29 - Karnataka'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount (₹)'), '1,250.50');
    // A new supplier starts as "I owe them".
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> sent = app.server.bodyOf('POST /parties')!;
    expect(sent['type'], 'supplier');
    expect(sent['gstin'], '29AABCU9603R1ZJ');
    expect(sent['state_code'], '29');
    expect(sent['opening_balance_paise'], -125050);
    expect(sent['id'], isA<String>());
    expect(find.byType(PartyFormScreen), findsNothing, reason: 'saved and closed');
  });

  testWidgets('party detail: ledger with running balance, payment received against a bill, cancel a payment',
      (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, PartyDetailScreen(partyId: 'p-ramesh', api: app.server.api));

    expect(find.text('₹1,200.00'), findsOneWidget);
    expect(find.text('To collect from them'), findsOneWidget);
    expect(find.text('Credit sale'), findsOneWidget);
    expect(find.text('+₹1,600.00'), findsOneWidget);
    expect(find.text('₹1,700.00 Dr'), findsOneWidget);
    expect(find.text('-₹500.00'), findsOneWidget);
    expect(find.text('₹1,200.00 Dr'), findsWidgets);
    expect(find.text('Opening balance'), findsOneWidget);

    await tester.tap(find.text('Payment received'));
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsWidgets);
    // Put it against the open credit bill: the amount due is filled in.
    await tester.tap(find.text('On account (no particular bill)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MED/26-27/000001 · ₹1,100.00 due').last);
    await tester.pumpAndSettle();
    expect(find.text('1100.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '1200');
    await tester.tap(find.text('UPI'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save payment'));
    await tester.tap(find.text('Save payment'));
    await tester.pumpAndSettle();
    expect(find.text('Only ₹1,100.00 is due on MED/26-27/000001'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount (₹)'), '500');
    await tester.enterText(find.widgetWithText(TextField, 'UPI reference (optional)'), 'UPI-99');
    await tester.tap(find.text('Save payment'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> pay = app.server.bodyOf('POST /payments')!;
    expect(<Object?>[pay['party_id'], pay['direction'], pay['amount_paise'], pay['mode'], pay['reference'], pay['bill_id']],
        <Object?>['p-ramesh', 'in', 50000, 'upi', 'UPI-99', 'b-1']);
    expect(find.byType(PartyDetailScreen), findsOneWidget);

    // Tapping a payment in the ledger offers to cancel it.
    await tester.tap(find.text('Payment received · UPI UPI-77'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel payment'));
    await tester.pumpAndSettle();
    expect(app.server.paths, contains('POST /payments/pay-1/cancel'));
    expect(find.text('Payment cancelled.'), findsOneWidget);
  });

  testWidgets('sale return: at most what is left, preview, credit note shown', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, ReturnScreen.sale(bill: _bill(), api: app.server.api));

    expect(find.textContaining('up to 2'), findsOneWidget, reason: '3 sold, 1 already returned');
    expect(find.text('Make credit note'), findsOneWidget);
    await tester.tap(find.byTooltip('One more Dolo 650'));
    await tester.tap(find.byTooltip('One more Dolo 650'));
    await tester.pump();
    final IconButton more = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_circle_outline));
    expect(more.onPressed, isNull, reason: 'no more than 2');
    // 2 x ₹112 at 12% inside: taxable 200.00, GST 24.00.
    expect(find.text('₹224.00'), findsOneWidget);
    // A cash bill is refunded in cash by default (no account to adjust).
    expect(find.text('Cash refund'), findsOneWidget);
    expect(find.text('Adjust in account'), findsNothing);
    await tester.tap(find.text('UPI refund'));
    await tester.enterText(find.widgetWithText(TextField, 'Reason (optional)'), 'Damaged strip');
    await tester.tap(find.text('Make credit note'));
    await tester.pumpAndSettle();

    final Map<String, dynamic> sent = app.server.bodyOf('POST /sale-returns')!;
    expect(sent['bill_id'], 'b-1');
    expect(sent['refund_mode'], 'upi');
    expect(sent['reason'], 'Damaged strip');
    expect(sent['lines'], <Object>[<String, Object>{'bill_item_id': 7, 'qty_units': 2}]);
    expect(find.byType(NoteDetailScreen), findsOneWidget);
    expect(find.text('Credit note CN/26-27/000001'), findsOneWidget);
    expect(find.text('Credit note saved. The items are back in stock.'), findsOneWidget);
    expect(find.text('Share PDF'), findsOneWidget);
  });

  testWidgets('credit bill return goes on the account', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, ReturnScreen.sale(bill: _bill(payment: 'credit', partyId: 'p-ramesh'), api: app.server.api));
    expect(find.text('A credit bill: the amount comes off the customer’s account.'), findsOneWidget);
    await tester.tap(find.text('Return all'));
    await tester.pump();
    await tester.tap(find.text('Make credit note'));
    await tester.pumpAndSettle();
    expect(app.server.bodyOf('POST /sale-returns')!['refund_mode'], 'credit');
  });

  testWidgets('purchases list, detail and a return to the supplier', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, PurchasesScreen(api: app.server.api));
    expect(find.text('Pune Pharma Distributors'), findsOneWidget);
    expect(find.text('₹504.00'), findsWidgets);

    await tester.tap(find.text('Pune Pharma Distributors'));
    await tester.pumpAndSettle();
    expect(find.byType(PurchaseDetailScreen), findsOneWidget);
    expect(find.text('Azithral 500'), findsOneWidget);
    expect(find.text('CGST (input)'), findsOneWidget);
    expect(find.text('₹504.00 to pay'), findsOneWidget);

    await tester.tap(find.text('Return to supplier'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Free goods are not returned here'), findsOneWidget);
    await tester.tap(find.byTooltip('One more Azithral 500'));
    await tester.pump();
    // Debit note preview: ₹50 less 10% + 12% GST = ₹50.40.
    expect(find.text('₹50.00'), findsOneWidget);
    await tester.tap(find.text('Make debit note'));
    await tester.pumpAndSettle();
    expect(app.server.bodyOf('POST /purchase-returns')!['lines'], <Object>[<String, Object>{'purchase_item_id': 11, 'qty': 1}]);
    expect(app.server.bodyOf('POST /purchase-returns')!['purchase_id'], 'pur-1');
    expect(find.text('Debit note DN/26-27/000001'), findsOneWidget);
  });

  testWidgets('GST reports: CA notice, GSTR-1 sections, GSTR-3B cash payable', (WidgetTester tester) async {
    final AccountsApp app = await start(tester);
    await app.open(tester, GstReportsScreen(api: app.server.api, now: DateTime(2026, 10, 5)));

    expect(find.textContaining('For review by your CA'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(app.server.requests.last.$2?['month'], '2026-10');
    expect(find.text('Lakshmi Clinic · 1 inv.'), findsOneWidget);
    expect(find.text('27 - Maharashtra · 5%'), findsOneWidget);
    expect(find.text('2 + 1 cancelled'), findsOneWidget);
    expect(find.text('Share CSV'), findsOneWidget);

    await tester.tap(find.text('GSTR-3B'));
    await tester.pumpAndSettle();
    expect(app.server.paths.last, 'GET /gst/gstr3b');
    expect(find.text('₹46.00'), findsWidgets);
    expect(find.text('ITC carried forward'), findsOneWidget);

    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026').last);
    await tester.pumpAndSettle();
    expect(app.server.requests.last.$2?['month'], '2026-09');
  });

  testWidgets('accounts screens: 48dp targets and labels', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final AccountsApp app = await start(tester, height: 2400);
    for (final Widget screen in <Widget>[
      PartiesScreen(api: app.server.api),
      PartyDetailScreen(partyId: 'p-ramesh', api: app.server.api),
      PartyFormScreen(api: app.server.api),
      PurchasesScreen(api: app.server.api),
      PurchaseDetailScreen(purchaseId: 'pur-1', api: app.server.api),
      ReturnScreen.sale(bill: _bill(), api: app.server.api),
      NoteDetailScreen(noteId: 'cn-1', sale: true, api: app.server.api),
      GstReportsScreen(api: app.server.api, now: DateTime(2026, 10, 5)),
    ]) {
      await tester.pumpWidget(app.wrap(screen));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '$screen');
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: '$screen');
    }
    semantics.dispose();
  });

  testWidgets('new bill: a credit bill needs a customer account, which fills the customer',
      (WidgetTester tester) async {
    final AccountsApp app = await start(tester, height: 2000);
    final DateTime now = DateTime.now();
    await app.medicines.add(Medicine(
      id: const Uuid().v4(),
      name: 'Dolo 650',
      unit: 'Strips',
      batchNo: 'B1',
      quantity: 10,
      sellingPrice: 30,
      expiryDate: DateTime(now.year + 2),
      createdAt: now,
      updatedAt: now,
    ));
    await app.open(
        tester,
        NewBillScreen(
          api: BillingApi(app.server.client),
          repository: BillingRepository(app.db),
          accountingApi: app.server.api,
        ));

    await tester.enterText(find.byType(TextField).first, 'dolo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolo 650'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create bill'));
    await tester.pumpAndSettle();
    expect(find.text("Choose the customer's account for a credit bill."), findsOneWidget);
    expect(app.server.paths, isNot(contains('POST /bills')));

    await tester.tap(find.text('Choose customer account (needed for credit)'));
    await tester.pumpAndSettle();
    expect(find.text('Choose customer'), findsOneWidget);
    expect(find.text('Pune Pharma Distributors'), findsNothing, reason: 'suppliers only are not listed');
    await tester.tap(find.text('Ramesh Kumar'));
    await tester.pumpAndSettle();
    expect(find.text('Account: Ramesh Kumar'), findsOneWidget);
    expect(find.widgetWithText(TextField, '9876543210'), findsOneWidget);

    await tester.tap(find.text('Create bill'));
    await tester.pumpAndSettle();
    final Map<String, dynamic> sent = app.server.bodyOf('POST /bills')!;
    expect(<Object?>[sent['payment_mode'], sent['party_id'], sent['customer_name'], sent['customer_phone']],
        <Object?>['credit', 'p-ramesh', 'Ramesh Kumar', '9876543210']);
  });

  group('a supplier bill typed by hand', () {
    Future<void> fill(WidgetTester tester, String label, String text) async {
      final Finder f = find.descendant(
          of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
          matching: find.byType(TextFormField));
      await tester.ensureVisible(f.first);
      await tester.enterText(f.first, text);
      await tester.pump();
    }

    Future<void> pickExpiry(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Not set').first);
      await tester.tap(find.text('Not set').first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '06/28');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('add items, choose the supplier, record the purchase',
        (WidgetTester tester) async {
      final AccountsApp app = await start(tester, height: 2000);
      await app.open(tester, InvoiceScanScreen.manual(accountingApi: app.server.api));

      expect(find.text('Enter supplier bill'), findsOneWidget);
      expect(find.text('Supplier bill, typed in'), findsOneWidget);
      expect(find.textContaining('No items yet'), findsOneWidget);
      expect(find.text('Choose supplier'), findsOneWidget);

      // A new medicine counted in tablets, 10 a strip.
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Add item'), findsWidgets, reason: 'the editor title');
      await fill(tester, 'Medicine name *', 'Azithral 500');
      await fill(tester, 'Manufacturer', 'Alembic');
      await fill(tester, 'Batch no.', 'AZ1');
      await fill(tester, 'Qty (packs) *', '10');
      await fill(tester, 'Free', '1');
      await fill(tester, 'Tablets per pack', '5');
      await fill(tester, 'MRP / pack', '119.50');
      await fill(tester, 'Rate / pack', '80');
      await pickExpiry(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 item'), findsWidgets);

      // An empty item can't be saved.
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget, reason: 'still in the editor');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pune Pharma Distributors'));
      await tester.pumpAndSettle();
      expect(find.text('Supplier: Pune Pharma Distributors'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, "Supplier's invoice no."), 'PPD/90');
      await tester.pump();

      await tester.tap(find.text('Record purchase (1)'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> sent = app.server.bodyOf('POST /purchases')!;
      expect(<Object?>[sent['party_id'], sent['supplier_invoice_no'], sent['invoice_scan_id']],
          <Object?>['p-ppd', 'PPD/90', null]);
      final Map<String, dynamic> line = (sent['lines'] as List<dynamic>).single as Map<String, dynamic>;
      expect(<Object?>[line['qty'], line['free_qty'], line['units_per_pack'], line['rate_paise'], line['mrp_paise'], line['batch_no']],
          <Object?>[10, 1, 5, 8000, 11950, 'AZ1']);
      expect(line['product'], containsPair('pack_size', 5));
      expect((line['product'] as Map<String, dynamic>)['unit'], 'Tablets');
      expect(find.byType(InvoiceScanScreen), findsNothing);
    });

    testWidgets('Purchases: one button, type the bill or scan it', (WidgetTester tester) async {
      final AccountsApp app = await start(tester);
      await app.open(tester, PurchasesScreen(api: app.server.api));
      await tester.tap(find.text('Add supplier bill'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a photo or PDF'), findsOneWidget);
      await tester.tap(find.text('Type the bill'));
      await tester.pumpAndSettle();
      expect(find.text('Enter supplier bill'), findsOneWidget);
    });

    testWidgets('an empty typed bill can be left without a question', (WidgetTester tester) async {
      final AccountsApp app = await start(tester);
      await app.open(tester, InvoiceScanScreen.manual(accountingApi: app.server.api));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceScanScreen), findsNothing);
    });
  });

  group('invoice scan records a purchase', () {
    const InvoiceScan scan = InvoiceScan(
      id: 5,
      status: 'done',
      result: <String, dynamic>{
        'supplier_name': 'Pune Pharma Distributors',
        'supplier_gstin': '27AABCU9603R1ZN',
        'invoice_no': 'PPD/77',
        'invoice_date': '2026-10-01',
        'items': <Object>[
          <String, dynamic>{
            'product_name': 'PAN 40 TAB',
            'manufacturer': 'Alkem',
            'pack': "15's",
            'batch_no': 'PN1',
            'expiry_date': '2028-01-31',
            'quantity': 4,
            'free_quantity': 1,
            'mrp': 150,
            'purchase_rate': 90.5,
            'discount_percent': 5,
            'gst_percent': 12,
            'hsn': '3004',
          },
        ],
      },
    );

    testWidgets('supplier found by GSTIN; stock comes from the server, not added here', (WidgetTester tester) async {
      final AccountsApp app = await start(tester);
      await app.open(tester, InvoiceScanScreen(initialScan: scan, accountingApi: app.server.api));

      expect(find.text('Supplier: Pune Pharma Distributors'), findsOneWidget);
      expect(find.text('Record purchase (1)'), findsOneWidget);
      await tester.tap(find.text('Record purchase (1)'));
      await tester.pumpAndSettle();

      final Map<String, dynamic> sent = app.server.bodyOf('POST /purchases')!;
      expect(<Object?>[sent['party_id'], sent['supplier_invoice_no'], sent['invoice_date'], sent['invoice_scan_id']],
          <Object?>['p-ppd', 'PPD/77', '2026-10-01', 5]);
      final Map<String, dynamic> line = (sent['lines'] as List<dynamic>).single as Map<String, dynamic>;
      expect(<Object?>[line['qty'], line['free_qty'], line['units_per_pack'], line['rate_paise'], line['mrp_paise'],
            line['discount_bp'], line['gst_rate_bp'], line['hsn'], line['batch_no'], line['expiry_date']],
          // Strips (the pack is the stock unit): rates and MRP per strip.
          <Object?>[4, 1, 1, 9050, 15000, 500, 1200, '3004', 'PN1', '2028-01-31']);
      expect((line['product'] as Map<String, dynamic>)['name'], 'PAN 40 TAB');
      // Nothing added locally: the server's batch and movements arrive by sync.
      expect(app.medicines.products, isEmpty);
      expect(find.byType(InvoiceScanScreen), findsNothing);
      expect(find.text('Purchase PPD/77 recorded: 1 item added to stock'), findsOneWidget);
    });

    testWidgets('an invoice entered before is not added again', (WidgetTester tester) async {
      final AccountsApp app = await start(tester);
      app.server.purchaseAnswer = (422, <String, Object?>{
        'message': 'Invoice PPD/77 from Pune Pharma Distributors is already entered.',
        'error': 'duplicate_invoice',
        'purchase_id': 'pur-1',
      });
      await app.open(tester, InvoiceScanScreen(initialScan: scan, accountingApi: app.server.api));
      await tester.tap(find.text('Record purchase (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Already entered'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(app.medicines.products, isEmpty);
      expect(find.byType(InvoiceScanScreen), findsOneWidget);

      // "Only add to stock" goes back to the local add.
      await tester.tap(find.byTooltip('Only add to stock'));
      await tester.pump();
      expect(find.text('Add 1 item'), findsOneWidget);
    });
  });
}
