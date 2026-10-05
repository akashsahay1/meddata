// Accessibility checks: 48x48dp touch targets, names on icon-only buttons,
// statuses readable by screen readers, text contrast, and no overflow with
// large system font sizes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/bill.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/data/repositories/billing_repository.dart';
import 'package:med_stock/presentation/screens/accounts/gst_reports_screen.dart';
import 'package:med_stock/presentation/screens/accounts/parties_screen.dart';
import 'package:med_stock/presentation/screens/accounts/party_detail_screen.dart';
import 'package:med_stock/presentation/screens/accounts/party_form_screen.dart';
import 'package:med_stock/presentation/screens/accounts/purchase_detail_screen.dart';
import 'package:med_stock/presentation/screens/accounts/purchases_screen.dart';
import 'package:med_stock/presentation/screens/add_edit_medicine_screen.dart';
import 'package:med_stock/presentation/screens/auth/forgot_password_screen.dart';
import 'package:med_stock/presentation/screens/auth/login_screen.dart';
import 'package:med_stock/presentation/screens/auth/signup_screen.dart';
import 'package:med_stock/presentation/screens/billing/bill_detail_screen.dart';
import 'package:med_stock/presentation/screens/billing/bills_screen.dart';
import 'package:med_stock/presentation/screens/billing/new_bill_screen.dart';
import 'package:med_stock/presentation/screens/billing/shop_settings_screen.dart';
import 'package:med_stock/presentation/screens/import/import_wizard_screen.dart';
import 'package:med_stock/presentation/screens/invoice_scan_screen.dart';
import 'package:med_stock/presentation/screens/lock_screen.dart';
import 'package:med_stock/presentation/screens/main_shell.dart';
import 'package:med_stock/presentation/screens/medicine_detail_screen.dart';
import 'package:med_stock/presentation/screens/onboarding_screen.dart';
import 'package:med_stock/presentation/screens/product_detail_screen.dart';
import 'package:med_stock/presentation/screens/reports_screen.dart';
import 'package:med_stock/presentation/screens/sync_issues_screen.dart';
import 'package:med_stock/presentation/screens/upgrade_screen.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:med_stock/services/invoice_scan_service.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/theme/app_theme.dart';

import '../billing_api_test.dart' show sampleBill;
import '../import/import_wizard_screen_test.dart' show pumpUntil;
import '../support/finders.dart';
import '../support/reports_fixture.dart';
import '../support/test_app.dart';

/// A screen to check, built over the seeded shop ([TestApp.seedShop]).
class _Screen {
  const _Screen(this.name, this.build,
      {this.tab,
      this.byTooltip = false,
      this.prepare,
      this.then,
      this.signedIn = false});
  final String name;

  /// Signed in, with the billing server answering ([_billingServer]).
  final bool signedIn;

  /// Steps after the screen is shown, to reach the state to check.
  final Future<void> Function(WidgetTester tester)? then;
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
  ..._reportTabs,
  _Screen('Sync issues', (_) => const SyncIssuesScreen()),
  _Screen('Login', (_) => const LoginScreen()),
  _Screen('Sign up', (_) => const SignupScreen()),
  _Screen('Forgot password', (_) => const ForgotPasswordScreen()),
  _Screen('Onboarding', (_) => const OnboardingScreen()),
  _Screen('Lock', (_) => const LockScreen()),
  _Screen('Upgrade', (_) => const UpgradeScreen()),
  // Accounts (signed out here: their "log in again" state; with data they
  // are checked in accounts_screens_test.dart).
  _Screen('Parties', (_) => const PartiesScreen()),
  _Screen('New party', (_) => const PartyFormScreen()),
  _Screen('Party detail', (_) => const PartyDetailScreen(partyId: 'p-1')),
  _Screen('Purchases', (_) => const PurchasesScreen()),
  _Screen('Purchase detail', (_) => const PurchaseDetailScreen(purchaseId: 'x')),
  _Screen('GST returns', (_) => const GstReportsScreen()),
];

/// The shop's server for the billing screens: shop details, one page of
/// bills (one of them cancelled) and a bill.
FakeBackend _billingServer() {
  final Map<String, Object?> bill = sampleBill();
  return FakeBackend(responses: <String, Object?>{
    '/shops/current': <String, Object?>{
      'shop': <String, Object?>{
        'name': 'Sahay Medicals',
        'legal_name': 'Sahay Medicals Pvt Ltd',
        'gstin': '27AAPFU0939F1ZV',
        'state_code': '27',
        'address': '12 Station Road, Pune',
        'phone': '020 1234567',
        'drug_license_no': 'MH-20B-12345',
        'invoice_prefix': 'MED',
        'default_gst_rate_bp': 500,
        'has_data': true,
      },
    },
    '/bills': <String, Object?>{
      'data': <Map<String, Object?>>[
        <String, Object?>{...bill, 'items_count': 2},
        <String, Object?>{
          ...bill,
          'id': 'b2',
          'invoice_no': 'MED/26-27/000041',
          'status': 'cancelled',
          'payment_mode': 'credit',
          'customer_name': 'Walk-in customer with a rather long name',
          'items_count': 12,
          'total_paise': 1234567,
        },
      ],
      'meta': <String, Object?>{'current_page': 1, 'last_page': 1, 'total': 2},
      'summary': <String, Object?>{
        'count': 1,
        'total_paise': 36400,
        'cancelled_count': 1,
      },
    },
    '/bills/${bill['id']}': <String, Object?>{'bill': bill},
  });
}

BillingApi _billing(TestApp app) => BillingApi(app.backend.api);

/// The counter screen over the seeded shop, online.
Widget _newBill(TestApp app) => NewBillScreen(
    api: _billing(app), repository: BillingRepository(app.db));

/// Adds Paracetamol 500 to the bill (FEFO picks the batch).
Future<void> _addToBill(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'para');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paracetamol 500').last);
  await tester.pumpAndSettle();
}

/// A read purchase invoice: one line matched to the shop's medicine, one
/// new and missing its expiry (marked to fix).
const InvoiceScan _readInvoice = InvoiceScan(
  id: 1,
  status: 'done',
  result: <String, dynamic>{
    'supplier_name': 'Shree Ganesh Pharma Distributors Private Limited',
    'invoice_no': 'SG/2026-27/001234',
    'invoice_date': '2026-10-01',
    'notes': 'Second page looks cut off.',
    'items': <Object>[
      <String, dynamic>{
        'product_name': 'PARACETAMOL 500 TAB',
        'manufacturer': 'MICRO LABS',
        'pack': "15's",
        'batch_no': 'PX1',
        'expiry_date': '2027-06-30',
        'quantity': 2,
        'free_quantity': 1,
        'mrp': 30,
        'purchase_rate': 20,
      },
      <String, dynamic>{
        'product_name': 'AZITHROMYCIN 500 MG TABLETS (STRIP OF 5)',
        'pack': "5's",
        'batch_no': 'AZ9',
        'expiry_date': null,
        'quantity': 4,
        'mrp': 119.5,
        'purchase_rate': 80,
      },
    ],
  },
);

/// A distributor's stock file: a title row, a batch the shop already has
/// (Paracetamol 500 P1), a row without expiry and a zero quantity.
Future<PickedSpreadsheet?> _stockFile() async => (
      name: 'Sharma Medical Agencies stock statement October.csv',
      bytes: Uint8List.fromList(utf8.encode(
          'Sharma Medical Agencies - Stock Statement\n'
          'Item Name,Pack,Mfr,Batch,Exp,Qty,MRP,Rate\n'
          "Paracetamol 500,15's,Micro Labs,P1,12/27,20,33.60,24\n"
          "Dolo 650,15's,Micro Labs,D2,01/28,5,33.60,24\n"
          'Azithral 500,5 TAB,Alembic,A9,,3,119.50,85\n'
          'ORS,SACHET,,O1,06/27,12,21,15\n'
          'Crocin,TAB,GSK,C1,06/27,0,25,18\n')),
    );

Future<void> _wizardTo(WidgetTester tester, int step) async {
  if (step < 2) return;
  await tester.tap(find.text('Choose file'));
  await pumpUntil(tester, find.text('Match columns'));
  if (step < 3) return;
  await tester.tap(find.text('Match columns'));
  await tester.pumpAndSettle();
  if (step < 4) return;
  await tester.tap(find.text('Check rows'));
  await pumpUntil(tester, find.textContaining('Step 4 of 4'));
  if (step < 5) return;
  await tester.tap(find.textContaining(RegExp(r'^Import \d+ rows?$')));
  await pumpUntil(tester, find.text('Import complete'));
}

_Screen _wizard(String name, int step) => _Screen(
    name, (_) => const ImportWizardScreen(pickFile: _stockFile),
    then: (WidgetTester tester) => _wizardTo(tester, step));

/// Screens added after the accessibility audit: billing, invoice reading,
/// the import wizard and the signed-in Profile.
final List<_Screen> _newScreens = <_Screen>[
  _Screen('Profile signed in', (_) => const MainShell(),
      tab: 'Profile', byTooltip: true, signedIn: true),
  _Screen('Bills', (TestApp app) => BillsScreen(api: _billing(app)),
      signedIn: true),
  _Screen('Bills offline',
      (TestApp app) => BillsScreen(api: BillingApi(FakeBackend().api)),
      signedIn: true),
  _Screen('New bill', _newBill, signedIn: true),
  _Screen('New bill with an item', _newBill,
      signedIn: true, then: _addToBill),
  _Screen('New bill offline',
      (TestApp app) => NewBillScreen(
          api: BillingApi(FakeBackend().api),
          repository: BillingRepository(app.db)),
      signedIn: true),
  _Screen('Bill detail',
      (TestApp app) => BillDetailScreen(
          bill: Bill.fromJson(sampleBill()), justCreated: true, api: _billing(app)),
      signedIn: true),
  _Screen('Bill detail cancelled',
      (TestApp app) => BillDetailScreen(
          bill: Bill.fromJson(sampleBill(status: 'cancelled')),
          api: _billing(app)),
      signedIn: true),
  _Screen('Shop settings',
      (TestApp app) => ShopSettingsScreen(api: _billing(app)),
      signedIn: true),
  _Screen('Invoice scan', (_) => const InvoiceScanScreen(), signedIn: true),
  _Screen('Invoice review',
      (_) => const InvoiceScanScreen(initialScan: _readInvoice),
      signedIn: true),
  _wizard('Import: choose file', 1),
  _wizard('Import: header row', 2),
  _wizard('Import: columns', 3),
  _wizard('Import: check rows', 4),
  _wizard('Import: done', 5),
];

/// The report tabs (stock valuation and expiry over the seeded shop; profit
/// signed out, and signed in with a server report).
AuthService? _profitAuth;
final List<_Screen> _reportTabs = <_Screen>[
  _Screen('Reports: valuation', (_) => const ReportsScreen(), tab: 'Valuation'),
  _Screen('Reports: expiry', (_) => const ReportsScreen(), tab: 'Expiry'),
  _Screen('Reports: profit signed out', (_) => const ReportsScreen(),
      tab: 'Profit'),
  _Screen('Reports: profit',
      (_) => signedInReports(_profitAuth!, profitServer(), initialTab: 2),
      prepare: (TestApp app) async =>
          _profitAuth = await signedInAuth(app, profitServer())),
];

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  setUpAll(loadAppFont);

  Future<TestApp> start(WidgetTester tester,
      {double height = 780, bool signedIn = false}) async {
    usePhoneScreen(tester, height: height);
    final TestApp app = await TestApp.create(
        signedIn: signedIn, backend: signedIn ? _billingServer() : null);
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
    await screen.then?.call(tester);
  }

  group('touch targets and labels', () {
    for (final _Screen screen in <_Screen>[
      ..._keyScreens,
      ..._otherScreens,
      ..._newScreens,
    ]) {
      testWidgets('${screen.name}: targets are 48x48dp and labelled',
          (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        // Tall enough to lay out the whole screen at once.
        final TestApp app =
            await start(tester, height: 2000, signedIn: screen.signedIn);
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

  group('billing, invoice reading and import read out names and amounts', () {
    _Screen named(String name) =>
        _newScreens.firstWhere((_Screen s) => s.name == name);

    Future<void> open(WidgetTester tester, String name) async {
      final _Screen screen = named(name);
      final TestApp app =
          await start(tester, height: 2000, signedIn: screen.signedIn);
      await show(tester, app, screen);
    }

    testWidgets('bills list: each bill with its amount and status in words',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await open(tester, 'Bills');
      expect(
          find.bySemanticsLabel(
              RegExp(r'^MED/26-27/000042\n.*City Clinic.*\n₹364\.00\nUPI$')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^MED/26-27/000041\n.*\n₹12,345\.67\nCancelled$')),
          findsOneWidget);
      expect(
          tester.getSemantics(find.text('Today')),
          isSemantics(
              label: 'Today', isButton: true, isSelected: true, hasTapAction: true));
      semantics.dispose();
    });

    testWidgets('new bill: icon buttons are named, payment is a choice',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await open(tester, 'New bill with an item');
      for (final String tip in <String>[
        'Remove Paracetamol 500',
        'One less',
        'One more',
        'Clear bill',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(
          tester.getSemantics(find.text('Cash')),
          isSemantics(
              label: 'Cash', isButton: true, isSelected: true, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('UPI'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text('UPI')),
          isSemantics(label: 'UPI', isSelected: true));
      semantics.dispose();
    });

    testWidgets('bill detail: payment, status and total are spoken',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await open(tester, 'Bill detail');
      expect(find.byTooltip('More actions'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Paid · UPI\n.*\nTotal\n₹364\.00$')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await open(tester, 'Bill detail cancelled');
      expect(find.bySemanticsLabel(RegExp(r'\nCancelled\n.*\nTotal\n₹364\.00$')),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('invoice review: buttons name their item, problems are spoken',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await open(tester, 'Invoice review');
      expect(find.byTooltip('Edit Paracetamol 500'), findsOneWidget);
      expect(find.byTooltip('Remove Paracetamol 500'), findsOneWidget);
      expect(
          find.byTooltip('Remove AZITHROMYCIN 500 MG TABLETS (STRIP OF 5)'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^AZITHROMYCIN 500 MG TABLETS.*Expiry date missing$', dotAll: true)),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('import: each column picker says which detail it is for',
        (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await open(tester, 'Import: columns');
      expect(
          find.bySemanticsLabel('Medicine name *\ne.g. Paracetamol 500\nA · Item Name'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Category\nNot in file'), findsOneWidget);
      expect(find.bySemanticsLabel('Unit for rows that have none\nTablets'),
          findsOneWidget);
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

  group('contrast on the screens added since the audit', () {
    for (final _Screen screen in _newScreens) {
      testWidgets('${screen.name} passes the text contrast guideline',
          (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TestApp app =
            await start(tester, height: 2000, signedIn: screen.signedIn);
        await show(tester, app, screen);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  });

  group('report tabs contrast', () {
    for (final _Screen screen in _reportTabs) {
      testWidgets('${screen.name} passes the text contrast guideline',
          (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        final TestApp app = await start(tester, height: 2400);
        await show(tester, app, screen);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  });

  group('large text', () {
    for (final double scale in <double>[1.3, 1.5]) {
      for (final _Screen screen in <_Screen>[
        ..._keyScreens,
        ..._otherScreens,
        ..._newScreens,
      ]) {
        testWidgets('${screen.name} fits at ${scale}x text',
            (WidgetTester tester) async {
          // A real phone screen, then a tall one that lays out every row.
          for (final double height in <double>[780, 2400]) {
            final TestApp app = await start(tester,
                height: height, signedIn: screen.signedIn);
            await show(tester, app, screen, textScale: scale);
            expect(tester.takeException(), isNull,
                reason: '${screen.name} at ${scale}x, 360x$height');
            await tester.pumpWidget(const SizedBox());
            // The in-memory database is shared until the test ends: start
            // the next size from an empty shop again.
            await app.db.clearAll();
          }
        });
      }
    }
  });
}
