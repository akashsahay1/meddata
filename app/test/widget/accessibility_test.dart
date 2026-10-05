// Accessibility checks: 48x48dp touch targets, names on icon-only buttons,
// statuses readable by screen readers, text contrast, and no overflow with
// large system font sizes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/presentation/screens/add_edit_medicine_screen.dart';
import 'package:med_stock/presentation/screens/auth/forgot_password_screen.dart';
import 'package:med_stock/presentation/screens/auth/login_screen.dart';
import 'package:med_stock/presentation/screens/auth/signup_screen.dart';
import 'package:med_stock/presentation/screens/lock_screen.dart';
import 'package:med_stock/presentation/screens/main_shell.dart';
import 'package:med_stock/presentation/screens/medicine_detail_screen.dart';
import 'package:med_stock/presentation/screens/onboarding_screen.dart';
import 'package:med_stock/presentation/screens/product_detail_screen.dart';
import 'package:med_stock/presentation/screens/reports_screen.dart';
import 'package:med_stock/presentation/screens/sync_issues_screen.dart';
import 'package:med_stock/presentation/screens/upgrade_screen.dart';
import 'package:med_stock/theme/app_theme.dart';

import '../support/finders.dart';
import '../support/test_app.dart';

/// A screen to check, built over the seeded shop ([TestApp.seedShop]).
class _Screen {
  const _Screen(this.name, this.build,
      {this.tab, this.byTooltip = false, this.prepare});
  final String name;
  final Widget Function(TestApp app) build;

  /// Bottom-bar tab to switch to, for screens inside the tab shell.
  final String? tab;

  /// Find [tab] by its tooltip instead of its text (an icon-only button).
  final bool byTooltip;

  /// Extra setup before the screen is shown.
  final Future<void> Function(TestApp app)? prepare;
}

Medicine _batch(TestApp app, String name) => app.medicines.visibleAllForAlerts
    .firstWhere((Medicine m) => m.name == name);

final _Screen _home = _Screen('Home', (_) => const MainShell());
final _Screen _inventory =
    _Screen('Inventory', (_) => const MainShell(), tab: 'Inventory');
final _Screen _editWithMfg = _Screen(
  // A batch with a manufacture date also shows the date's clear button and
  // the delete button.
  'Edit medicine',
  (TestApp app) => AddEditMedicineScreen(
      existing: _batch(app, 'Cetirizine').copyWith(mfgDate: day(-90)),
      api: app.backend.api),
);
final _Screen _medicineDetail = _Screen('Medicine detail',
    (TestApp app) => MedicineDetailScreen(medicineId: _batch(app, 'Dolo 650').id));

/// The screens a shop owner uses every day.
final List<_Screen> _keyScreens = <_Screen>[
  _home,
  _Screen('Home on trial', (_) => const MainShell(),
      prepare: (TestApp app) async {
    await app.settings.setPremium(false);
    await app.settings.setTrialEndsAt(day(5));
  }),
  _inventory,
  _Screen('Alerts', (_) => const MainShell(), tab: 'Alerts'),
  _Screen('Add medicine',
      (TestApp app) => AddEditMedicineScreen(api: app.backend.api)),
  _editWithMfg,
  _Screen('Product detail', (TestApp app) => ProductDetailScreen(
      productId: _batch(app, 'Paracetamol 500').productId)),
  _medicineDetail,
];

/// Everything else, checked with the same rules.
final List<_Screen> _otherScreens = <_Screen>[
  // No bottom-bar tab for Profile on phones: it opens from the Home avatar.
  _Screen('Profile', (_) => const MainShell(), tab: 'Profile', byTooltip: true),
  _Screen('Reports', (_) => const ReportsScreen()),
  _Screen('Sync issues', (_) => const SyncIssuesScreen()),
  _Screen('Login', (_) => const LoginScreen()),
  _Screen('Sign up', (_) => const SignupScreen()),
  _Screen('Forgot password', (_) => const ForgotPasswordScreen()),
  _Screen('Onboarding', (_) => const OnboardingScreen()),
  _Screen('Lock', (_) => const LockScreen()),
  _Screen('Upgrade', (_) => const UpgradeScreen()),
];

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadAppFont);

  Future<TestApp> start(WidgetTester tester, {double height = 780}) async {
    usePhoneScreen(tester, height: height);
    final TestApp app = await TestApp.create();
    addTearDown(app.dispose);
    await app.seedShop();
    return app;
  }

  Future<void> show(WidgetTester tester, TestApp app, _Screen screen,
      {double textScale = 1}) async {
    await screen.prepare?.call(app);
    await tester.pumpWidget(app.wrap(screen.build(app), textScale: textScale));
    await tester.pumpAndSettle();
    if (screen.tab != null) {
      await tester.tap(screen.byTooltip
          ? find.byTooltip(screen.tab!)
          : find.text(screen.tab!));
      await tester.pumpAndSettle();
    }
  }

  group('touch targets and labels', () {
    for (final _Screen screen in <_Screen>[..._keyScreens, ..._otherScreens]) {
      testWidgets('${screen.name}: targets are 48x48dp and labelled',
          (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        // Tall enough to lay out the whole screen at once.
        final TestApp app = await start(tester, height: 2000);
        await show(tester, app, screen);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }

    testWidgets('filter chips: 48dp tall, announce count and selection',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester);
      await show(tester, app, _inventory);

      // The guideline skips the chips (they touch their scroll view's edges),
      // so check them directly.
      for (final String chip in <String>[
        'All · 5',
        'Low stock · 3',
        'Expiring soon · 1',
        'Expired · 1',
      ]) {
        expect(tester.getSemantics(find.text(chip)).rect.height,
            greaterThanOrEqualTo(48),
            reason: chip);
      }
      expect(
          tester.getSemantics(find.text('Low stock · 3')),
          isSemantics(
              label: 'Low stock, 3',
              isButton: true,
              isSelected: false,
              hasTapAction: true));

      // A screen reader's double-tap selects it.
      tester.semantics.tap(find.semantics.byLabel('Low stock, 3'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text('Low stock · 3')),
          isSemantics(label: 'Low stock, 3', isSelected: true));
      expect(tileNames(tester), <String>['Cetirizine', 'Dolo 650', 'ORS']);
      semantics.dispose();
    });

    testWidgets('icon-only buttons have names', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester);
      await show(tester, app, _home);
      expect(find.byTooltip('Profile'), findsOneWidget);
      expect(find.byTooltip('Add medicine'), findsOneWidget);
      expect(find.bySemanticsLabel('Sync: Not synced'), findsOneWidget);
      expect(find.bySemanticsLabel('Alerts, 5 need attention'), findsOneWidget,
          reason: 'the badge count is announced with the tab');

      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scan barcode'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'para');
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('stock +/- buttons are named and work from a screen reader',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester);
      final Medicine dolo = _batch(app, 'Dolo 650');
      await show(tester, app, _medicineDetail);
      expect(find.byTooltip('Edit medicine'), findsOneWidget);
      expect(find.byTooltip('Delete medicine'), findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('Add 1 to stock'));
      await tester.pumpAndSettle();
      expect(app.medicines.findById(dolo.id)!.quantity, 6);
      tester.semantics.tap(find.semantics.byLabel('Remove 1 from stock'));
      await tester.pumpAndSettle();
      expect(app.medicines.findById(dolo.id)!.quantity, 5);

      // A finger on the button, or in the extra touch area around it, acts
      // once.
      await tester.tap(find.byTooltip('Add 1 to stock'));
      await tester.pumpAndSettle();
      expect(app.medicines.findById(dolo.id)!.quantity, 6);
      final Rect edit = tester.getRect(find.byTooltip('Edit medicine'));
      await tester.tapAt(edit.topLeft + const Offset(2, 2)); // outside the 38dp box
      await tester.pumpAndSettle();
      expect(find.byType(AddEditMedicineScreen), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('date fields read out their label and value',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester, height: 2000);
      await show(tester, app, _editWithMfg);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^Manufacture date: \d\d \w{3} \d{4}$')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Expiry date: \d\d \w{3} \d{4}$')),
          findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('Clear manufacture date'));
      await tester.pump();
      expect(find.bySemanticsLabel('Manufacture date: Not set'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('statuses are spoken, not only coloured', () {
    testWidgets('each row announces its status in words',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester, height: 2000);
      await show(tester, app, _inventory);

      String row(String name) => tester.getSemantics(find.text(name)).label;
      expect(row('Cetirizine'), contains('Low stock'));
      expect(row('Dolo 650'), contains('Expired'));
      expect(row('ORS'), contains('Out of stock'));
      expect(row('Paracetamol 500'), contains('Expiring soon'));
      expect(row('Azithral 500'), contains('In stock'));
      // The initials avatar is decoration, not read out first.
      expect(row('Cetirizine'), startsWith('Cetirizine'));
      semantics.dispose();
    });

    testWidgets('home alert cards read as "label: count"',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester);
      await show(tester, app, _home);
      expect(find.bySemanticsLabel('Low on stock: 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Expiring soon: 1'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('contrast (WCAG AA: 4.5:1 for normal text)', () {
    test('muted text on cards, the screen background and dark headers', () {
      expect(_contrast(AppColors.muted, AppColors.card),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.muted, AppColors.canvas),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.onDarkMuted, AppColors.green),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.onDarkFaint, AppColors.greenDarkest),
          greaterThanOrEqualTo(4.5));
    });

    testWidgets('home search hint on its translucent pill',
        (WidgetTester tester) async {
      final TestApp app = await start(tester);
      await show(tester, app, _home);
      final Color hint = tester
          .widget<Text>(find.text('Search or add medicine'))
          .style!
          .color!;
      // The pill is white at 12% over the green header.
      final Color pill = Color.alphaBlend(
          Colors.white.withValues(alpha: 0.12), AppColors.green);
      expect(_contrast(hint, pill), greaterThanOrEqualTo(4.5));
    });

    testWidgets('Home and Inventory pass the text contrast guideline',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final TestApp app = await start(tester);
      await show(tester, app, _home);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  });

  group('large text', () {
    for (final double scale in <double>[1.3, 1.5]) {
      for (final _Screen screen in <_Screen>[..._keyScreens, ..._otherScreens]) {
        testWidgets('${screen.name} fits at ${scale}x text',
            (WidgetTester tester) async {
          // A real phone screen, then a tall one that lays out every row.
          for (final double height in <double>[780, 2400]) {
            final TestApp app = await start(tester, height: height);
            await show(tester, app, screen, textScale: scale);
            expect(tester.takeException(), isNull,
                reason: '${screen.name} at ${scale}x, 360x$height');
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });
}
