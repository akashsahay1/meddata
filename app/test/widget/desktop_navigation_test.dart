import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/presentation/screens/accounts/parties_screen.dart';
import 'package:medikabiz/presentation/screens/accounts/party_form_screen.dart';
import 'package:medikabiz/presentation/screens/add_edit_medicine_screen.dart';
import 'package:medikabiz/presentation/screens/home_screen.dart';
import 'package:medikabiz/presentation/screens/main_shell.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadAppFont);

  Future<TestApp> start(
    WidgetTester tester,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = scale;
    tester.view.physicalSize = size * scale;
    addTearDown(tester.view.reset);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    return app;
  }

  for (final Size size in <Size>[const Size(900, 620), const Size(1280, 800)]) {
    testWidgets('Add medicine is a centered desktop form at $size', (
      WidgetTester tester,
    ) async {
      final TestApp app = await start(tester, size, scale: 1.5);
      await tester.pumpWidget(app.wrap(const HomeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search or add medicine'));
      await tester.pumpAndSettle();

      final Rect form = tester.getRect(find.byType(AddEditMedicineScreen));
      expect(form.width, lessThanOrEqualTo(760));
      expect(form.height, lessThan(size.height));
      expect(form.center.dx, closeTo(size.width / 2, 0.1));
      expect(
        find.byType(HomeScreen),
        findsOneWidget,
        reason: 'the main screen stays visible behind the form',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AddEditMedicineScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the desktop rail also opens a compact Add medicine form', (
    WidgetTester tester,
  ) async {
    final TestApp app = await start(tester, const Size(1280, 800));
    await tester.pumpWidget(app.wrap(const MainShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add medicine'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AddEditMedicineScreen)).width,
      lessThanOrEqualTo(760),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer and supplier forms are compact on desktop', (
    WidgetTester tester,
  ) async {
    final TestApp app = await start(tester, const Size(1280, 800));
    await tester.pumpWidget(app.wrap(const PartiesScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PartyFormScreen)).width,
      lessThanOrEqualTo(760),
    );
    expect(find.byType(PartiesScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones still open Add medicine as a full page', (
    WidgetTester tester,
  ) async {
    final TestApp app = await start(tester, const Size(360, 780));
    await tester.pumpWidget(app.wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search or add medicine'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(AddEditMedicineScreen)),
      const Size(360, 780),
    );
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
