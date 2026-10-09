import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/core/formatters.dart';
import 'package:med_stock/presentation/screens/alerts_screen.dart';
import 'package:med_stock/presentation/screens/home_screen.dart';
import 'package:med_stock/presentation/screens/reports_screen.dart';
import 'package:med_stock/presentation/screens/inventory_screen.dart';
import 'package:med_stock/presentation/screens/product_detail_screen.dart';
import 'package:med_stock/presentation/widgets/ui_kit.dart';

import '../support/finders.dart';
import '../support/test_app.dart';

void main() {
  setUpAll(loadAppFont);

  // See [TestApp.seedShop] for what the seeded shop holds.
  Future<TestApp> start(WidgetTester tester, {bool seeded = true}) async {
    usePhoneScreen(tester, height: 1400);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    if (seeded) await app.seedShop();
    return app;
  }

  group('home', () {
    testWidgets('summary cards count medicines, stock value and alerts',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(cardValue(StatCard, 'Medicines', '5'), findsOneWidget);
      expect(find.text('2 categories'), findsOneWidget);
      // 71 units at ₹30 each.
      expect(cardValue(StatCard, 'Stock value', '₹2,130'), findsOneWidget);
      expect(find.text('71 units'), findsOneWidget);
      expect(cardValue(AlertCard, 'Low on stock', '3'), findsOneWidget);
      expect(cardValue(AlertCard, 'Expiring soon', '1'), findsOneWidget);

      // The stock value card opens Reports.
      await tester.tap(find.text('Stock value'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsScreen), findsOneWidget);
    });

    testWidgets('needs attention lists each problem medicine, worst first',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(tileNames(tester),
          <String>['Dolo 650', 'Paracetamol 500', 'ORS', 'Cetirizine']);
      expect(tileStatuses(tester),
          <String>['Expired', 'Expiring', 'Out of stock', 'Low']);
      expect(find.text('All good'), findsNothing);

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertsScreen), findsOneWidget);
    });

    testWidgets('an empty shop shows zeros and "All good"',
        (WidgetTester tester) async {
      final TestApp app = await start(tester, seeded: false);
      await tester.pumpWidget(app.wrap(const HomeScreen()));
      await tester.pumpAndSettle();

      expect(cardValue(StatCard, 'Medicines', '0'), findsOneWidget);
      expect(find.text('0 categories'), findsOneWidget);
      expect(cardValue(AlertCard, 'Low on stock', '0'), findsOneWidget);
      expect(cardValue(AlertCard, 'Expiring soon', '0'), findsOneWidget);
      expect(find.text('All good'), findsOneWidget);
      expect(find.byType(MedicineTile), findsNothing);
    });
  });

  group('inventory', () {
    testWidgets('lists every medicine once with status, stock and expiry',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const InventoryScreen()));
      await tester.pumpAndSettle();

      expect(tileNames(tester), <String>[
        'Azithral 500',
        'Cetirizine',
        'Dolo 650',
        'ORS',
        'Paracetamol 500',
      ]);
      expect(tileStatuses(tester),
          <String>['In stock', 'Low', 'Expired', 'Out of stock', 'Expiring']);
      final MedicineTile para = tester.widget<MedicineTile>(
          find.widgetWithText(MedicineTile, 'Paracetamol 500'));
      expect(para.qtyLabel, '12 Tablets', reason: 'both batches together');
      expect(para.subtitle, contains('2 batches'));
      expect(para.expLabel, 'Exp ${Fmt.dateShort(day(20))}',
          reason: 'the batch that expires first');

      // Filter chips carry the counts.
      for (final String chip in <String>[
        'All · 5',
        'Low stock · 3',
        'Expiring soon · 1',
        'Expired · 1',
      ]) {
        expect(find.text(chip), findsOneWidget);
      }
    });

    testWidgets('search narrows the list and can be cleared',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const InventoryScreen()));
      await tester.pumpAndSettle();
      final Finder search = find.byType(TextField);

      await tester.enterText(search, 'para');
      await tester.pump();
      expect(tileNames(tester), <String>['Paracetamol 500']);

      await tester.enterText(search, 'b-77'); // a batch number
      await tester.pump();
      expect(tileNames(tester), <String>['Cetirizine']);

      await tester.enterText(search, 'CIPLA'); // a brand
      await tester.pump();
      expect(tileNames(tester), <String>['Cetirizine']);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(tileNames(tester), hasLength(5));
      expect(app.medicines.query, isEmpty);
    });

    testWidgets('status filters show only the matching medicines',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const InventoryScreen()));
      await tester.pumpAndSettle();

      Future<List<String>> filter(String chip) async {
        await tapChip(tester, chip);
        return tileNames(tester);
      }

      expect(await filter('Low stock · 3'), <String>['Cetirizine', 'Dolo 650', 'ORS']);
      expect(await filter('Expiring soon · 1'), <String>['Paracetamol 500']);
      expect(await filter('Expired · 1'), <String>['Dolo 650']);
      expect(await filter('All · 5'), hasLength(5));

      // Filter and search combine.
      await filter('Low stock · 3');
      await tester.enterText(find.byType(TextField), 'ors');
      await tester.pump();
      expect(tileNames(tester), <String>['ORS']);
    });

    testWidgets('empty states say why the list is empty',
        (WidgetTester tester) async {
      final TestApp app = await start(tester, seeded: false);
      await tester.pumpWidget(app.wrap(const InventoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No medicines yet'), findsOneWidget);
      expect(
          find.text('Tap the + button to add your first item, or bring in '
              'your stock list from a spreadsheet.'),
          findsOneWidget);
      expect(find.text('Import from Excel / CSV'), findsOneWidget);
      expect(find.text('All · 0'), findsOneWidget);

      await app.addBatch('Cetirizine', qty: 50);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No medicines match'), findsOneWidget);
      expect(find.text('Try a different search.'), findsOneWidget);

      await tapChip(tester, 'Expired · 0');
      expect(find.text('Try a different search or filter.'), findsOneWidget);
    });

    testWidgets('tapping a medicine opens its batches',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await tester.pumpWidget(app.wrap(const InventoryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paracetamol 500'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(find.text('in stock across 2 batches'), findsOneWidget);
      expect(find.text('Batch P1'), findsOneWidget);
      expect(find.text('Batch P2'), findsOneWidget);
    });
  });
}
