import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/presentation/screens/reports_screen.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';

import '../support/reports_fixture.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(loadAppFont);

  Future<TestApp> start(WidgetTester tester) async {
    usePhoneScreen(tester, height: 2400);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    // Seeded at MRP ₹30 and purchase rate ₹18 per unit (see seedShop).
    await app.seedShop();
    return app;
  }

  Future<void> openTab(WidgetTester tester, TestApp app, String tab,
      {Widget? screen}) async {
    await tester.pumpWidget(app.wrap(screen ?? const ReportsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  testWidgets('overview counts medicines, not batches, and every category',
      (WidgetTester tester) async {
    usePhoneScreen(tester, height: 2400);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    // One medicine with three batches, then nine more in nine categories.
    for (final String b in <String>['D1', 'D2', 'D3']) {
      await app.addBatch('Dolo 650', batch: b, category: 'Antipyretic (Fever)');
    }
    const List<String> cats = <String>[
      'Antibiotic', 'Antacid / Gastro', 'Cough & Cold', 'Allergy / Antihistamine',
      'Diabetes', 'Cardiac / Blood Pressure', 'Vitamins & Supplements',
      'Dermatology / Skin', 'First Aid',
    ];
    for (int i = 0; i < cats.length; i++) {
      await app.addBatch('Medicine $i', category: cats[i]);
    }
    await tester.pumpWidget(app.wrap(const ReportsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('10'), findsWidgets, reason: '10 medicines (12 batches)');
    expect(find.text('12'), findsNothing);
    expect(find.text('10 categories'), findsOneWidget,
        reason: 'all categories, not just the eight in the chart');
  });

  testWidgets('valuation: stock at cost and MRP, expired apart, by category',
      (WidgetTester tester) async {
    final TestApp app = await start(tester);
    await openTab(tester, app, 'Valuation');

    expect(find.text('As of today'), findsOneWidget);
    // Sellable: 6 + 6 + 4 + 50 = 66 units.
    expect(find.text('₹1,188.00'), findsOneWidget); // x ₹18
    expect(find.text('₹1,980.00'), findsOneWidget); // x ₹30
    // Expiring within 30 days: Paracetamol P2, 6 units.
    expect(find.text('₹108.00'), findsWidgets);
    // Expired: Dolo 650, 5 units.
    expect(find.text('at cost · ₹150.00 MRP'), findsOneWidget);
    expect(find.text('Expired stock'), findsOneWidget);
    // Categories by MRP value.
    expect(find.text('Antibiotic'), findsOneWidget);
    expect(find.text('Pain Relief / Analgesic'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
  });

  testWidgets('expiry: windows, and writing off expired stock',
      (WidgetTester tester) async {
    final TestApp app = await start(tester);
    await openTab(tester, app, 'Expiry');

    expect(find.text('Next 30 days'), findsOneWidget);
    expect(find.text('Next 90 days'), findsOneWidget);
    expect(find.text('Expired stock to write off'), findsOneWidget);
    expect(find.text('Dolo 650'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Write off Dolo 650, batch D1'));
    await tester.pumpAndSettle();
    expect(find.text('Write off Dolo 650?'), findsOneWidget);
    expect(find.textContaining('expiry loss of ₹90.00 at cost'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Write off'));
    await tester.pumpAndSettle();

    expect(find.text('Wrote off 5 units of expired stock.'), findsOneWidget);
    final Medicine dolo = app.medicines.visibleAllForAlerts
        .firstWhere((Medicine m) => m.name == 'Dolo 650');
    expect(dolo.quantity, 0);
    expect(find.text('Expired stock to write off'), findsNothing);
    // Recorded as a loss, by the month it expired.
    final Finder writtenOff = find.ancestor(
        of: find.text('Written off so far'), matching: find.byType(Column));
    expect(find.descendant(of: writtenOff.first, matching: find.text('₹90.00')),
        findsOneWidget);
    expect(find.textContaining('Cost ₹90.00 · 5 units'), findsOneWidget);
  });

  testWidgets('profit: signed out and offline messages',
      (WidgetTester tester) async {
    final TestApp app = await start(tester);
    await openTab(tester, app, 'Profit');
    expect(find.text('Log in to see profit'), findsOneWidget);

    final ApiClient offline = profitServer(online: false);
    final AuthService auth = await signedInAuth(app, offline);
    await openTab(tester, app, 'Profit',
        screen: signedInReports(auth, offline));
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.textContaining('needs the internet'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('profit: totals, margin, unknown cost flagged, breakdowns',
      (WidgetTester tester) async {
    final TestApp app = await start(tester);
    final List<Uri> asked = <Uri>[];
    final ApiClient server = profitServer(requests: asked);
    final AuthService auth = await signedInAuth(app, server);
    await openTab(tester, app, 'Profit', screen: signedInReports(auth, server));

    expect(asked.single.path, endsWith('/reports/profit'));
    expect(find.text('₹78.35'), findsOneWidget); // gross profit
    expect(find.text('Margin 23.86%'), findsOneWidget);
    expect(find.text('₹375.97'), findsOneWidget); // revenue excl. GST
    expect(find.text('Some sales have no purchase rate'), findsOneWidget);
    expect(find.textContaining('Mystery Tonic (MT1): 1 sold'), findsOneWidget);
    expect(find.text('By day'), findsOneWidget);
    expect(find.text('Cough Syrup'), findsOneWidget);
    expect(find.text('Cough & Cold'), findsOneWidget);

    // Another range asks again.
    await tester.tap(find.text('Last 7 days'));
    await tester.pumpAndSettle();
    expect(asked, hasLength(2));
  });

  testWidgets('reports stay locked without Premium', (WidgetTester tester) async {
    final TestApp app = await start(tester);
    await app.settings.setPremium(false);
    await tester.pumpWidget(app.wrap(const ReportsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Reports are a Premium feature'), findsOneWidget);
    expect(find.text('Valuation'), findsNothing);
  });
}
