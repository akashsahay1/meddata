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
    await _plugin.initialize(settings);
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
    await _plugin.show(id, title, body, _details);
  }

  /// Runs the digest: counts expiring/expired/low-stock and posts one summary.
  Future<void> runDailyDigest({
    int warningDays = 30,
    bool notifyExpiry = true,
    bool notifyLowStock = true,
  }) async {
    await init();
    final MedicineRepository repo = MedicineRepository();
    final List<Medicine> all = await repo.getAll();

    int expired = 0, expiring = 0, low = 0;
    for (final Medicine m in all) {
      final MedicineStatus s =
          MedicineStatus.of(m, warningDays: warningDays);
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
    if (parts.isEmpty) return;

    await showNow(
      1001,
      'Medicine Stock Alert',
      'You have ${parts.join(', ')}. Tap to review.',
    );
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
        m.id.hashCode & 0x7fffffff,
        'Expiry approaching',
        '${m.name} expires on ${m.expiryDate.day}/${m.expiryDate.month}/${m.expiryDate.year}.',
        when,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleExpiryReminder failed: $e');
    }
  }

  Future<void> cancelAll() async => _plugin.cancelAll();
}
