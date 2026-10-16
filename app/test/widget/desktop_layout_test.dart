// On a PC window the main tabs use desktop layouts (full width, tables,
// columns), not the phone's single column of cards; phones keep the cards.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/accounts/gst_reports_screen.dart';
import 'package:medikabiz/presentation/screens/accounts/parties_screen.dart';
import 'package:medikabiz/presentation/screens/accounts/purchases_screen.dart';
import 'package:medikabiz/presentation/screens/alerts_screen.dart';
import 'package:medikabiz/presentation/screens/billing/bills_screen.dart';
import 'package:medikabiz/presentation/screens/main_shell.dart';
import 'package:medikabiz/presentation/screens/product_detail_screen.dart';
import 'package:medikabiz/presentation/screens/reports_screen.dart';
import 'package:medikabiz/presentation/widgets/desktop_kit.dart';
import 'package:medikabiz/presentation/widgets/ui_kit.dart';
import 'package:medikabiz/theme/app_theme.dart';
import 'package:medikabiz/services/billing_api.dart';

import '../billing_api_test.dart' show sampleBill;
import '../support/test_app.dart';

FakeBackend _billingServer() {
  final Map<String, Object?> bill = sampleBill();
  return FakeBackend(responses: <String, Object?>{
    '/bills': <String, Object?>{
      'data': <Map<String, Object?>>[
        <String, Object?>{...bill, 'items_count': 2},
        <String, Object?>{
          ...bill,
          'id': 'b2',
          'invoice_no': 'MED/26-27/000041',
          'status': 'cancelled',
          'items_count': 1,
        },
      ],
      'meta': <String, Object?>{'current_page': 1, 'last_page': 1, 'total': 2},
      'summary': <String, Object?>{'count': 1, 'total_paise': 36400, 'cancelled_count': 1},
    },
  });
}

void main() {
  setUpAll(loadAppFont);

  /// The seeded shop in the tab shell, on a [size] window.
  Future<TestApp> open(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final TestApp app = await TestApp.create(signedIn: true, backend: _billingServer());
    addTearDown(app.dispose);
    await app.seedShop();
    await tester.pumpWidget(app.wrap(const MainShell()));
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  const Size fullHd = Size(1920, 1080);

  /// Width the page content gets next to the 228px side menu, less gutters.
  double contentWidth(WidgetTester tester, Finder f) => tester.getRect(f.first).width;

  group('desktop window', () {
    testWidgets('the rail shows the hand over its tabs; Add medicine is white on orange',
        (WidgetTester tester) async {
      await open(tester, fullHd);
      final TestGesture mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
          location: tester.getCenter(find
              .descendant(of: find.byType(NavigationRail), matching: find.text('Bills'))));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click);

      final Finder add = find.widgetWithText(ElevatedButton, 'Add medicine');
      final ButtonStyle style = tester.widget<ElevatedButton>(add).style ??
          const ButtonStyle();
      final ButtonStyle theme = Theme.of(tester.element(add)).elevatedButtonTheme.style!;
      final Color? fg = (style.foregroundColor ?? theme.foregroundColor)!.resolve(<WidgetState>{});
      final Color? bg = (style.backgroundColor ?? theme.backgroundColor)!.resolve(<WidgetState>{});
      expect(fg, Colors.white);
      expect(bg, AppColors.orangeButton);
    });

    // Parties, Purchases, Reports and GST returns were only inside
    // Profile -> Accounts, where owners could not find them.
    for (final Size size in <Size>[fullHd, const Size(1000, 600)]) {
      testWidgets('the rail opens every main screen as a tab at $size',
          (WidgetTester tester) async {
        await open(tester, size);
        final NavigationRail rail =
            tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(
          <String>[
            for (final NavigationRailDestination d in rail.destinations)
              ((d.label as MouseRegion).child! as Text).data!,
          ],
          <String>['Home', 'Inventory', 'Bills', 'Parties', 'Purchases',
              'Reports', 'GST returns', 'Alerts', 'Profile'],
        );
        for (final (String name, Type screen) in <(String, Type)>[
          ('Parties', PartiesScreen),
          ('Purchases', PurchasesScreen),
          ('Reports', ReportsScreen),
          ('GST returns', GstReportsScreen),
        ]) {
          final Finder item = find
              .descendant(of: find.byType(NavigationRail), matching: find.text(name));
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(find.byType(screen), findsOneWidget, reason: name);
          expect(find.byType(BackButton), findsNothing, reason: '$name is a tab');
          expect(find.byType(CloseButton), findsNothing, reason: '$name is a tab');
        }
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text('Alerts')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertsScreen), findsOneWidget,
            reason: 'Alerts is still reachable after the new tabs');
        expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 7);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Home is a dashboard: numbers, a "Needs attention" table and quick actions',
        (WidgetTester tester) async {
      await open(tester, fullHd);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('MEDICINE'), findsOneWidget, reason: 'table headings');
      expect(find.text('Dolo 650'), findsOneWidget);
      expect(find.byType(MedicineTile), findsNothing, reason: 'no phone cards');
      expect(contentWidth(tester, find.byType(DeskPageHeader)), greaterThan(1500),
          reason: 'uses the window, not a centred 1200px column');
    });

    testWidgets('Inventory is a table across the window; a row opens the medicine',
        (WidgetTester tester) async {
      await open(tester, fullHd);
      await tab(tester, 'Inventory');
      for (final String heading in <String>[
        'MEDICINE', 'CATEGORY', 'STOCK', 'BATCHES', 'MRP', 'NEAREST EXPIRY', 'STATUS',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(find.byType(MedicineTile), findsNothing);
      expect(contentWidth(tester, find.byType(DeskTable)), greaterThan(1500));
      // Search and the filters sit on one line above the table.
      expect(tester.getCenter(find.text('Search medicines')).dy,
          closeTo(tester.getCenter(find.text('All · 5')).dy, 4));

      await tester.tap(find.text('Dolo 650'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductDetailScreen), findsOneWidget);
    });

    testWidgets('Bills is a table with the period totals above it',
        (WidgetTester tester) async {
      // The bills come from the (fake) server; the shell's tab would use the
      // real one, so the screen is shown on its own at the shell's width.
      final TestApp app = await TestApp.create(signedIn: true, backend: _billingServer());
      addTearDown(app.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = fullHd;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app.wrap(BillsScreen(api: BillingApi(app.backend.api))));
      await tester.pumpAndSettle();
      for (final String heading in <String>[
        'INVOICE NO.', 'DATE & TIME', 'CUSTOMER', 'ITEMS', 'PAYMENT', 'AMOUNT',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(find.text('MED/26-27/000041'), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('Sales'), findsOneWidget);
      expect(contentWidth(tester, find.byType(DeskTable)), greaterThan(1500));
    });

    testWidgets('Alerts shows expired, expiring and low stock side by side',
        (WidgetTester tester) async {
      await open(tester, fullHd);
      await tab(tester, 'Alerts');
      final List<Offset> titles = <Offset>[
        for (final String t in <String>['Expired', 'Expiring soon', 'Low on stock'])
          tester.getTopLeft(find.descendant(
              of: find.byType(Scaffold).last, matching: find.text(t)).first),
      ];
      expect(titles[0].dy, closeTo(titles[1].dy, 1));
      expect(titles[1].dy, closeTo(titles[2].dy, 1));
      expect(titles[0].dx < titles[1].dx && titles[1].dx < titles[2].dx, isTrue);
    });

    testWidgets('Profile puts its settings in two columns', (WidgetTester tester) async {
      await open(tester, fullHd);
      await tab(tester, 'Profile');
      final Offset account = tester.getTopLeft(find.text('ACCOUNT'));
      final Offset appearance = tester.getTopLeft(find.text('APPEARANCE'));
      expect(appearance.dx, greaterThan(account.dx + 500), reason: 'second column');
      expect(appearance.dy, lessThan(account.dy + 200), reason: 'side by side, not below');
    });
  });

  testWidgets('a phone keeps the cards', (WidgetTester tester) async {
    await open(tester, const Size(390, 900));
    await tab(tester, 'Inventory');
    expect(find.byType(MedicineTile), findsWidgets);
    expect(find.byType(DeskTable), findsNothing);
  });
}
