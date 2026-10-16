// The optional pharmacist and FSSAI details in Shop & invoice details: read
// and saved with the shop, and printed on invoices.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/data/models/bill.dart';
import 'package:medikabiz/presentation/screens/billing/shop_settings_screen.dart';
import 'package:medikabiz/services/api_client.dart';
import 'package:medikabiz/services/billing_api.dart';
import 'package:medikabiz/services/invoice_pdf.dart';

import 'billing_api_test.dart' show sampleBill;
import 'support/test_app.dart';

/// Serves the shop's details and keeps what Save sends.
class _ShopServer extends ApiClient {
  _ShopServer(this.shop);

  Map<String, dynamic> shop;
  Map<String, dynamic>? patched;

  @override
  Future<({int status, Map<String, dynamic>? body})> currentShop(String token) async =>
      (status: 200, body: <String, dynamic>{'shop': shop});

  @override
  Future<({int status, Map<String, dynamic>? body})> updateShop(
      String token, Map<String, dynamic> changes) async {
    patched = changes;
    shop = <String, dynamic>{...shop, ...changes};
    return (status: 200, body: <String, dynamic>{'shop': shop});
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the shop profile reads and writes the pharmacist and FSSAI details', () {
    final ShopProfile p = ShopProfile.fromJson(<String, dynamic>{
      'name': 'Sahay Medicals',
      'pharmacist_name': 'Ravi Kumar',
      'pharmacist_reg_no': 'JH/PH/1234',
      'pharmacist_reg_date': '2019-04-15',
      'pharmacist_qualification': 'B.Pharm',
      'fssai_license_no': '10123456789012',
    });
    expect(p.pharmacistName, 'Ravi Kumar');
    expect(p.pharmacistRegDate, DateTime(2019, 4, 15));
    expect(p.toJson(), allOf(
      containsPair('pharmacist_reg_no', 'JH/PH/1234'),
      containsPair('pharmacist_reg_date', '2019-04-15'),
      containsPair('pharmacist_qualification', 'B.Pharm'),
      containsPair('fssai_license_no', '10123456789012'),
    ));
    expect(const ShopProfile(name: 'X').toJson()['pharmacist_reg_date'], isNull);
  });

  test('the invoice prints the pharmacist lines that are set', () {
    SellerDetails seller(Map<String, dynamic> j) =>
        SellerDetails.fromJson(<String, dynamic>{'name': 'Sahay Medicals', ...j});

    expect(
      seller(<String, dynamic>{
        'pharmacist_name': 'Ravi Kumar',
        'pharmacist_qualification': 'B.Pharm',
        'pharmacist_reg_no': 'JH/PH/1234',
        'pharmacist_reg_date': '2019-04-15',
      }).pharmacistLines,
      <String>['Pharmacist: Ravi Kumar (B.Pharm)', 'Reg. No.: JH/PH/1234 dated 15-04-2019'],
    );
    expect(seller(<String, dynamic>{'pharmacist_name': 'Ravi Kumar'}).pharmacistLines,
        <String>['Pharmacist: Ravi Kumar']);
    expect(seller(<String, dynamic>{'pharmacist_reg_date': '2019-04-15'}).pharmacistLines,
        <String>['Registered on 15-04-2019']);
    expect(seller(<String, dynamic>{}).pharmacistLines, isEmpty);
  });

  test('invoices with the pharmacist and FSSAI details still render', () async {
    final InvoiceFonts fonts = await InvoiceFonts.load();
    final Map<String, dynamic> raw = sampleBill();
    raw['seller'] = <String, dynamic>{
      ...(raw['seller'] as Map<String, dynamic>),
      'pharmacist_name': 'Ravi Kumar',
      'pharmacist_reg_no': 'JH/PH/1234',
      'pharmacist_reg_date': '2019-04-15',
      'pharmacist_qualification': 'B.Pharm',
      'fssai_license_no': '10123456789012',
    };
    final Bill bill = Bill.fromJson(raw);
    expect(bill.seller.fssaiLicenseNo, '10123456789012');
    for (final InvoiceLayout layout in InvoiceLayout.values) {
      final Uint8List pdf = await InvoicePdf.build(bill, layout: layout, fonts: fonts);
      expect(pdf.length, greaterThan(1000), reason: '$layout');
    }
  });

  testWidgets('Shop & invoice details shows, checks and saves the pharmacist and FSSAI fields',
      (WidgetTester tester) async {
    usePhoneScreen(tester, height: 2600);
    final TestApp app = await TestApp.create(signedIn: true);
    addTearDown(app.dispose);
    final _ShopServer server = _ShopServer(<String, dynamic>{
      'name': 'Sahay Medicals',
      'state_code': '27',
      'default_gst_rate_bp': 500,
      'pharmacist_name': 'Ravi Kumar',
      'pharmacist_reg_date': '2019-04-15',
    });
    await app.open(tester, ShopSettingsScreen(api: BillingApi(server)));

    TextEditingController field(String label) =>
        tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!;

    expect(find.text('Pharmacist & FSSAI (optional)'), findsOneWidget);
    expect(field('Pharmacist name').text, 'Ravi Kumar');
    expect(find.text('15 Apr 2019'), findsOneWidget);

    // The date can be cleared.
    await tester.tap(find.byTooltip('Clear the registration date'));
    await tester.pump();
    expect(find.text('15 Apr 2019'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Qualification'), 'D.Pharm');
    await tester.enterText(find.widgetWithText(TextFormField, 'FSSAI licence no.'), '1012345678901');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('An FSSAI licence number has 14 digits'), findsOneWidget);
    expect(server.patched, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'FSSAI licence no.'), '10123456789012');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(server.patched, allOf(
      containsPair('pharmacist_name', 'Ravi Kumar'),
      containsPair('pharmacist_reg_no', null),
      containsPair('pharmacist_reg_date', null),
      containsPair('pharmacist_qualification', 'D.Pharm'),
      containsPair('fssai_license_no', '10123456789012'),
    ));
    expect(find.text('Invoice details saved'), findsOneWidget);
  });
}
