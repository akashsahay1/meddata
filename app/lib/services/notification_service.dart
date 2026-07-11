import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repositories/medicine_repository.dart';
import '../data/models/medicine.dart';
import '../domain/medicine_status.dart';

/// Wraps local notifications: daily digest + per-item expiry reminders.
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

  /// Local time of day (24h) at which the repeating daily digest fires.
  static const int _digestHour = 9;

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
    const InitializationSettings settings =
        InitializationSettings(android: android, iOS: ios);
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

  /// Builds the digest body from the current medicine list, or null when there
  /// is nothing worth reporting under the given preferences.
  Future<String?> _buildDigestBody({
    required int warningDays,
    required bool notifyExpiry,
    required bool notifyLowStock,
  }) async {
    final MedicineRepository repo = MedicineRepository();
    final List<Medicine> all = await repo.getAll();

    int expired = 0, expiring = 0, low = 0;
    for (final Medicine m in all) {
      final MedicineStatus s = MedicineStatus.of(m, warningDays: warningDays);
      if (s.isExpired) {
        expired++;
      } else if (s.isExpiring) {
        expiring++;
      }
      if (s.isLowStock) low++;
    }

    final List<String> parts = <String>[];
    if (notifyExpiry && expired > 0) parts.add('$expired expired');
    if (notifyExpiry && expiring > 0) parts.add('$expiring expiring soon');
    if (notifyLowStock && low > 0) parts.add('$low low on stock');
    if (parts.isEmpty) return null;

    return 'You have ${parts.join(', ')}. Tap to review.';
  }

  /// Computes the next occurrence of the digest hour in local time.
  tz.TZDateTime _nextDigestTime() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      _digestHour,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Runs the digest now: counts expiring/expired/low-stock and posts one
  /// summary immediately.
  Future<void> runDailyDigest({
    int warningDays = 30,
    bool notifyExpiry = true,
    bool notifyLowStock = true,
  }) async {
    await init();
    final String? body = await _buildDigestBody(
      warningDays: warningDays,
      notifyExpiry: notifyExpiry,
      notifyLowStock: notifyLowStock,
    );
    if (body == null) return;
    await showNow(_digestNotificationId, 'Medicine Stock Alert', body);
  }

  /// Schedules a daily repeating digest notification at a fixed local time.
  ///
  /// Without background execution the body is a snapshot recomputed each time
  /// this is called (i.e. on app launch). It cancels any prior digest first,
  /// then schedules a repeating notification only when there is something to
  /// report.
  Future<void> scheduleDailyDigest({
    int warningDays = 30,
    bool notifyExpiry = true,
    bool notifyLowStock = true,
  }) async {
    await init();
    await _plugin.cancel(id: _digestNotificationId);

    final String? body = await _buildDigestBody(
      warningDays: warningDays,
      notifyExpiry: notifyExpiry,
      notifyLowStock: notifyLowStock,
    );
    if (body == null) return;

    try {
      await _plugin.zonedSchedule(
        id: _digestNotificationId,
        title: 'Medicine Stock Alert',
        body: body,
        scheduledDate: _nextDigestTime(),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('scheduleDailyDigest failed: $e');
    }
  }

  /// Cancels the repeating daily digest notification.
  Future<void> cancelDailyDigest() async {
    await init();
    await _plugin.cancel(id: _digestNotificationId);
  }

  /// Schedules a reminder for a single medicine's expiry window.
  Future<void> scheduleExpiryReminder(Medicine m, int warningDays) async {
    await init();
    final DateTime target =
        m.expiryDate.subtract(Duration(days: warningDays));
    if (target.isBefore(DateTime.now())) return;
    final tz.TZDateTime when = tz.TZDateTime.from(target, tz.local);
    try {
      await _plugin.zonedSchedule(
        id: m.id.hashCode & 0x7fffffff,
        title: 'Expiry approaching',
        body:
            '${m.name} expires on ${m.expiryDate.day}/${m.expiryDate.month}/${m.expiryDate.year}.',
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('scheduleExpiryReminder failed: $e');
    }
  }

  Future<void> cancelAll() async => _plugin.cancelAll();
}
