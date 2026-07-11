import 'notification_service.dart';

/// Thin facade over [NotificationService] for the daily digest.
///
/// The digest is delivered by a repeating local notification scheduled through
/// flutter_local_notifications; there is no background isolate anymore.
class BackgroundWorker {
  const BackgroundWorker._();

  /// Retained for call-site compatibility. Notification setup happens in
  /// [NotificationService.init], so there is nothing to do here.
  static Future<void> init() async {}

  /// Schedules the repeating daily digest notification.
  static Future<void> scheduleDailyDigest({
    required int warningDays,
    required bool notifExpiry,
    required bool notifLowStock,
  }) async {
    await NotificationService.instance.scheduleDailyDigest(
      warningDays: warningDays,
      notifyExpiry: notifExpiry,
      notifyLowStock: notifLowStock,
    );
  }

  /// Cancels the repeating daily digest notification.
  static Future<void> cancel() async =>
      NotificationService.instance.cancelDailyDigest();
}
