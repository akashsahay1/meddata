// Smoke test of the main flow on one device, no server needed: add a
// medicine from the tab shell, find it on Home and in Inventory, then check
// the expiry alerts planned and scheduled for it. The notifications plugin
// is replaced by a fake platform channel, so nothing native runs.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/core/formatters.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/domain/expiry_alert_plan.dart';
import 'package:med_stock/presentation/screens/add_edit_medicine_screen.dart';
import 'package:med_stock/presentation/screens/main_shell.dart';
import 'package:med_stock/presentation/widgets/ui_kit.dart';
import 'package:med_stock/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/finders.dart';
import '../support/test_app.dart';

const MethodChannel _notifications =
    MethodChannel('dexterous.com/flutter/local_notifications');

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(loadAppFont);

  testWidgets('add a medicine -> listed -> expiry alerts planned and scheduled',
      (WidgetTester tester) async {
    usePhoneScreen(tester, height: 1400);

    // NotificationService reads the inventory through the app's default
    // database, so the app runs on that one too (in memory).
    sqfliteFfiInit();
    DatabaseHelper.factoryOverride = databaseFactoryFfiNoIsolate;
    DatabaseHelper.pathOverride = inMemoryDatabasePath;
    addTearDown(() {
      DatabaseHelper.factoryOverride = null;
      DatabaseHelper.pathOverride = null;
    });
    final TestApp app = await TestApp.create(db: DatabaseHelper.instance);
    addTearDown(app.dispose);

    // Fake Android notifications (tests run as Android): the plugin's
    // Android side talks over this channel, which records every call.
    final List<MethodCall> calls = <MethodCall>[];
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _notifications, (MethodCall call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_notifications, null));

    await tester.pumpWidget(app.wrap(const MainShell()));
    await tester.pumpAndSettle();
    expect(find.text('All good'), findsOneWidget);

    // 1. Add: 8 tablets (low stock at 10), expiring in 45 days.
    final DateTime expiry = day(45);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditMedicineScreen), findsOneWidget);
    await tester.enterText(fieldLabeled('Medicine name *'), 'Azithral 500');
    await tester.enterText(fieldLabeled('Quantity *'), '8');
    await tester.enterText(fieldLabeled('Selling price (MRP)'), '95');
    await tester.tap(dateField('Expiry date *'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final MaterialLocalizations l10n = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)));
    await tester.enterText(
        find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField)),
        l10n.formatCompactDate(expiry));
    await answerDialog(tester, 'OK');
    expect(find.text(Fmt.date(expiry)), findsOneWidget);
    await tester.tap(find.text('Add medicine'));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditMedicineScreen), findsNothing);

    // 2. Listed: on Home it is counted and needs attention (low stock)...
    expect(cardValue(StatCard, 'Medicines', '1'), findsOneWidget);
    expect(cardValue(AlertCard, 'Low on stock', '1'), findsOneWidget);
    expect(cardValue(AlertCard, 'Expiring soon', '0'), findsOneWidget);
    expect(tileNames(tester), <String>['Azithral 500']);
    expect(tileStatuses(tester), <String>['Low']);

    // ...and in Inventory with its stock and expiry.
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    final MedicineTile row = tester
        .widget<MedicineTile>(find.widgetWithText(MedicineTile, 'Azithral 500'));
    expect(row.qtyLabel, '8 Tablets');
    expect(row.priceLabel, '₹95');
    expect(row.expLabel, 'Exp ${Fmt.dateShort(expiry)}');

    // 3. Alert plan: the day it enters the 30-day window, and the day after
    // it expires.
    final List<AlertDay> plan = planExpiryAlerts(
      app.medicines.visibleAllForAlerts,
      warningDays: app.settings.warningDays,
      today: DateTime.now(),
    );
    expect(plan.map((AlertDay a) => a.day), <DateTime>[day(15), day(46)]);
    expect(plan.map((AlertDay a) => a.message), <String>[
      '1 medicine is now expiring soon. Tap to review.',
      '1 medicine has expired. Tap to review.',
    ]);

    // 4. Scheduling: old alerts cleared, then the daily digest and one alert
    // per plan day, all at the chosen reminder time.
    await app.settings.setReminderTime(const TimeOfDay(hour: 8, minute: 30));
    await NotificationService.instance.refreshAll(
      warningDays: app.settings.warningDays,
      notifyExpiry: app.settings.notifExpiry,
      notifyLowStock: app.settings.notifLowStock,
      hour: app.settings.reminderHour,
      minute: app.settings.reminderMinute,
    );
    expect(calls.where((MethodCall c) => c.method == 'cancel'), hasLength(61));
    final List<Map<Object?, Object?>> scheduled = <Map<Object?, Object?>>[
      for (final MethodCall c in calls)
        if (c.method == 'zonedSchedule') c.arguments as Map<Object?, Object?>,
    ];
    expect(scheduled.map((Map<Object?, Object?> s) => s['id']),
        <int>[1001, 2000, 2001]);

    final Map<Object?, Object?> digest = scheduled[0];
    expect(digest['body'], 'You have 1 low on stock. Tap to review.');
    expect(digest['matchDateTimeComponents'], DateTimeComponents.time.index,
        reason: 'repeats daily');
    expect(digest['scheduledDateTime'] as String, endsWith('T08:30:00'));

    for (int i = 0; i < plan.length; i++) {
      final Map<Object?, Object?> alert = scheduled[i + 1];
      expect(alert['body'], plan[i].message);
      expect(alert['scheduledDateTime'], '${_ymd(plan[i].day)}T08:30:00');
      expect(alert['matchDateTimeComponents'], isNull, reason: 'one-off');
    }
    expect(scheduled.map((Map<Object?, Object?> s) => s['timeZoneName']).toSet(),
        <String>{'Asia/Kolkata'});
  });
}
