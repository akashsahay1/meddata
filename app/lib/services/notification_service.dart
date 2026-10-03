import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repositories/medicine_repository.dart';
import '../data/models/medicine.dart';
import '../domain/expiry_alert_plan.dart';
import '../domain/medicine_status.dart';
import '../domain/product_stock.dart';

/// Wraps local notifications: the daily digest plus pre-scheduled
/// expiry-day alerts, all built on the device (no server involved).
/// All notifications are plain text (monochrome design has no bearing here,
/// but we keep messaging simple and clear).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const String _channelId = 'med_stock_alerts';
  static const String _channelName = 'Stock & Expiry Alerts';

  /// Stable id for the daily digest notification so it can be updated and
  /// cancelled deterministically.
  static const int _digestNotificationId = 1001;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await _deviceTimeZone()));
    } catch (_) {
      // Fall back to UTC if the platform timezone can't be resolved.
    }

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings ios = DarwinInitializationSettings();
    // Windows toasts need an app identity; the GUID must stay fixed.
    const WindowsInitializationSettings windows = WindowsInitializationSettings(
      appName: 'Meddata',
      appUserModelId: 'Meddata.MedicineStock',
      guid: 'f9033c7c-2a2e-4eba-a999-7a5e7b2653e4',
    );
    const InitializationSettings settings = InitializationSettings(
        android: android, iOS: ios, windows: windows);
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<String> _deviceTimeZone() async {
    // Kept simple; default to Asia/Kolkata for the primary market, safe fallback.
    return 'Asia/Kolkata';
  }

  Future<bool> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final bool granted =
        await android?.requestNotificationsPermission() ?? true;
    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return granted;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Expiry and low-stock reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  Future<void> showNow(int id, String title, String body) async {
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  /// First id of the pre-scheduled expiry-day alerts (one per day, max 60).
  static const int _planBaseId = 2000;
  static const int _planMax = 60;

  /// Rebuilds every scheduled alert from the current inventory and the
  /// user's settings. Call after inventory changes (local edits or sync)
  /// and when alert settings change.
  ///
  /// - One notification for each upcoming day on which a batch starts
  ///   expiring or expires (computed now from expiry dates, so it fires on
  ///   time even if the app isn't opened).
  /// - The repeating daily digest at the chosen time, with today's counts.
  Future<void> refreshAll({
    required int warningDays,
    required bool notifyExpiry,
    required bool notifyLowStock,
    required int hour,
    required int minute,
  }) async {
    await init();
    for (int i = 0; i < _planMax; i++) {
      await _plugin.cancel(id: _planBaseId + i);
    }
    await _plugin.cancel(id: _digestNotificationId);

    final List<Medicine> all = await MedicineRepository().getAll();
    final String? digest = _digestBody(all,
        warningDays: warningDays,
        notifyExpiry: notifyExpiry,
        notifyLowStock: notifyLowStock);
    if (digest != null) {
      await _schedule(_digestNotificationId, digest, _nextAt(hour, minute),
          repeatDaily: true);
    }

    if (!notifyExpiry) return;
    final List<AlertDay> plan = planExpiryAlerts(all,
        warningDays: warningDays, today: DateTime.now());
    for (int i = 0; i < plan.length && i < _planMax; i++) {
      final AlertDay a = plan[i];
      await _schedule(
          _planBaseId + i,
          a.message,
          tz.TZDateTime(tz.local, a.day.year, a.day.month, a.day.day, hour, minute));
    }
  }

  tz.TZDateTime _nextAt(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime at =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  Future<void> _schedule(int id, String body, tz.TZDateTime when,
      {bool repeatDaily = false}) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: 'Medicine Stock Alert',
        body: body,
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
      );
    } catch (e) {
      debugPrint('schedule notification $id failed: $e');
    }
  }

  String? _digestBody(List<Medicine> all,
      {required int warningDays,
      required bool notifyExpiry,
      required bool notifyLowStock}) {
    // Same rules as the app: expiry counts batches that still have stock;
    // low stock counts medicines by their total across batches.
    int expired = 0, expiring = 0;
    for (final Medicine m in all.where((Medicine m) => m.quantity > 0)) {
      final MedicineStatus s = MedicineStatus.of(m, warningDays: warningDays);
      if (s.isExpired) {
        expired++;
      } else if (s.isExpiring) {
        expiring++;
      }
    }
    final int low =
        ProductStock.group(all).where((ProductStock p) => p.isLowStock).length;
    final List<String> parts = <String>[];
    if (notifyExpiry && expired > 0) parts.add('$expired expired');
    if (notifyExpiry && expiring > 0) parts.add('$expiring expiring soon');
    if (notifyLowStock && low > 0) parts.add('$low low on stock');
    if (parts.isEmpty) return null;
    return 'You have ${parts.join(', ')}. Tap to review.';
  }

  /// Cancels the repeating daily digest notification.
  Future<void> cancelDailyDigest() async {
    await init();
    await _plugin.cancel(id: _digestNotificationId);
  }

  Future<void> cancelAll() async => _plugin.cancelAll();
}
