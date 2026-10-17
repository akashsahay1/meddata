// Screenshots of the real app for the website (backend/public/images/screens).
// The screens are the app's own widgets over a made-up shop, so no real
// customer data appears and they can be retaken after any design change:
//
//   cd app && flutter test tool/website_screenshots_test.dart
//
// then shrink them to the WebP files the website uses (and drop the PNGs):
//
//   cd backend/public/images && php -r 'foreach (glob("screens/*.png") as $f) {
//     $i = new Imagick($f); $i->resizeImage(str_contains($f, "desktop") ? 1600 : 780, 0,
//     Imagick::FILTER_LANCZOS, 1); $i->setImageFormat("webp");
//     $i->setImageCompressionQuality(86); $i->writeImage(substr($f, 0, -4).".webp"); unlink($f); }'
//
// Not part of the test suite (it lives outside test/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medikabiz/data/repositories/billing_repository.dart';
import 'package:medikabiz/presentation/screens/billing/new_bill_screen.dart';
import 'package:medikabiz/presentation/screens/main_shell.dart';
import 'package:medikabiz/presentation/screens/supplier_bills_screen.dart';
import 'package:medikabiz/services/billing_api.dart';
import 'package:medikabiz/services/invoice_scan_service.dart';

import '../test/billing_api_test.dart' show sampleBill;
import '../test/support/test_app.dart';

const String _out = '../backend/public/images/screens';

/// A believable medical shop: strips priced per strip, a few medicines low,
/// a couple expiring soon, one expired.
Future<void> _seed(TestApp app) async {
  Future<void> add(String name, String brand, String category, int qty,
      double mrp, int days,
      {int pack = 15, String unit = 'Tablets', int low = 30, String batch = ''}) =>
      app.addBatch(name,
          brand: brand,
          category: category,
          qty: qty * 8, // a full shelf, not a sample
          mrp: mrp,
          purchase: (mrp * 0.72 * 100).round() / 100,
          expiresInDays: days,
          packSize: pack,
          unit: unit,
          lowStock: low,
          batch: batch.isEmpty ? 'B${name.length}${qty}7' : batch);
  await add('Dolo 650', 'Micro Labs', 'Antipyretic (Fever)', 450, 33.60, 420, batch: 'DOBS3975');
  await add('Pan 40', 'Alkem', 'Antacid / Gastro', 300, 165.00, 510);
  await add('Azithral 500', 'Alembic', 'Antibiotic', 40, 119.50, 300, pack: 5, low: 10);
  await add('Augmentin 625 Duo', 'GSK', 'Antibiotic', 8, 223.40, 24, pack: 10, low: 20);
  await add('Telma 40', 'Glenmark', 'Cardiac / Blood Pressure', 180, 249.00, 380);
  await add('Glycomet GP 1', 'USV', 'Diabetes', 120, 152.00, 290);
  await add('Shelcal 500', 'Torrent', 'Vitamins & Supplements', 6, 128.00, 330);
  await add('Benadryl Cough Syrup', 'Johnson & Johnson', 'Cough & Cold', 14, 142.00, 260,
      pack: 1, unit: 'Bottles', low: 5);
  await add('Allegra 120', 'Sanofi', 'Allergy / Antihistamine', 60, 238.00, 450, pack: 10);
  await add('Montair LC', 'Cipla', 'Allergy / Antihistamine', 3, 210.00, 400, pack: 10, low: 20);
  await add('Cetzine 10', "Dr. Reddy's", 'Allergy / Antihistamine', 200, 22.50, 610, pack: 10);
  await add('Ecosprin 75', 'USV', 'Cardiac / Blood Pressure', 280, 5.10, 540, pack: 14);
  await add('Combiflam', 'Sanofi', 'Pain Relief / Analgesic', 160, 44.00, 18, pack: 20);
  await add('Digene Gel Mint', 'Abbott', 'Antacid / Gastro', 9, 162.00, -5,
      pack: 1, unit: 'Bottles', low: 5);
  await add('Electral ORS', 'FDC', 'Uncategorised', 0, 22.00, 300, pack: 1, unit: 'Sachets', low: 10);
  await add('Thyronorm 50', 'Abbott', 'Diabetes', 240, 215.00, 700, pack: 120, low: 60);
}

final GlobalKey _frame = GlobalKey();

Future<TestApp> _app(WidgetTester tester, Size size, double dpr,
    {FakeBackend? backend}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  // A phone's status bar and gesture bar, so the app lays out as on a real
  // phone; the website draws the status icons into that band.
  if (size.width < 600) {
    final FakeViewPadding bars = FakeViewPadding(top: 36 * dpr, bottom: 20 * dpr);
    tester.view.padding = bars;
    tester.view.viewPadding = bars;
  }
  addTearDown(tester.view.reset);
  final TestApp app = await TestApp.create(signedIn: true, backend: backend);
  addTearDown(app.dispose);
  app.sync.lastSuccess = DateTime.now(); // a working shop shows 'Synced'
  await _seed(app);
  return app;
}

Future<void> _show(WidgetTester tester, TestApp app, Widget screen) async {
  await tester.pumpWidget(RepaintBoundary(key: _frame, child: app.wrap(screen)));
  await tester.pumpAndSettle();
  // Let asset images (the logo) decode, then paint them.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String name) async {
  final RenderRepaintBoundary boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image =
        await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
    final File file = File('$_out/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

FakeBackend _billing() => FakeBackend(responses: <String, Object?>{
      '/shops/current': <String, Object?>{
        'shop': <String, Object?>{
          'name': 'City Care Medical Store',
          'gstin': '09AQKPS4821M1Z6',
          'state_code': '09',
          'address': '12 Station Road, Aminabad, Lucknow',
          'phone': '0522 4012233',
          'drug_license_no': 'UP3220B000412',
          'invoice_prefix': 'CCM',
          'default_gst_rate_bp': 1200,
          'has_data': true,
        },
      },
      '/bills': <String, Object?>{
        'data': <Map<String, Object?>>[<String, Object?>{...sampleBill(), 'items_count': 2}],
        'meta': <String, Object?>{'current_page': 1, 'last_page': 1, 'total': 1},
        'summary': <String, Object?>{'count': 1, 'total_paise': 36400, 'cancelled_count': 0},
      },
    });

void main() {
  setUpAll(() async {
    await loadAppFont();
    final FontLoader icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  const Size desktop = Size(1440, 900);
  const Size phone = Size(390, 844);

  testWidgets('desktop: home and inventory', (WidgetTester tester) async {
    final TestApp app = await _app(tester, desktop, 2);
    await _show(tester, app, const MainShell());
    await _save(tester, 'desktop-home');
    await _tab(tester, 'Inventory');
    await _save(tester, 'desktop-inventory');
  });

  testWidgets('phone: home and alerts', (WidgetTester tester) async {
    final TestApp app = await _app(tester, phone, 3);
    await _show(tester, app, const MainShell());
    await _save(tester, 'phone-home');
    await _tab(tester, 'Alerts');
    await _save(tester, 'phone-alerts');
  });

  testWidgets('phone: a bill at the counter', (WidgetTester tester) async {
    final TestApp app = await _app(tester, phone, 3, backend: _billing());
    await _show(
      tester,
      app,
      NewBillScreen(api: BillingApi(app.backend.api), repository: BillingRepository(app.db)),
    );
    for (final String q in <String>['dolo', 'allegra', 'pan 4']) {
      await tester.enterText(find.byType(TextField).first, q);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(RegExp(q, caseSensitive: false)).last);
      await tester.pumpAndSettle();
    }
    await _save(tester, 'phone-new-bill');
  });

  testWidgets('phone: supplier bills being read', (WidgetTester tester) async {
    final TestApp app = await _app(tester, phone, 3);
    final InvoiceScanService service = InvoiceScanService(
      baseUrl: 'http://api.test',
      client: MockClient((http.Request r) async => http.Response(
          '{"scans":['
          '{"id":5,"status":"processing","file_name":"gupta_medicos.pdf","created_at":"2026-10-17T10:05:00+05:30"},'
          '{"id":4,"status":"queued","retrying":true,"file_name":"IMG_0412.jpg","created_at":"2026-10-17T10:04:00+05:30"},'
          '{"id":3,"status":"done","supplier_name":"Arogya Healthcare LLP","invoice_no":"AHL/26-27/2241","items_count":48,"created_at":"2026-10-17T09:58:00+05:30"},'
          '{"id":2,"status":"done","supplier_name":"Om Sai Medical Agencies","invoice_no":"OSMA-26-11873","items_count":10,"created_at":"2026-10-17T09:57:00+05:30"},'
          '{"id":1,"status":"done","supplier_name":"Shree Balaji Pharma","invoice_no":"SBP/2627/04518","items_count":8,"created_at":"2026-10-17T09:55:00+05:30"}'
          ']}',
          200,
          headers: <String, String>{'content-type': 'application/json; charset=utf-8'})),
    );
    await _show(tester, app, SupplierBillsScreen(service: service));
    await _save(tester, 'phone-supplier-bills');
    await tester.pumpWidget(const SizedBox()); // stops the list's refresh timer
  });
}
