import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';

const String kDailyDigestTask = 'med_stock_daily_digest';

/// Entry point invoked by WorkManager in a background isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    if (task == kDailyDigestTask) {
      final int warningDays = (input?['warningDays'] as int?) ?? 30;
      final bool notifExpiry = (input?['notifExpiry'] as bool?) ?? true;
      final bool notifLow = (input?['notifLowStock'] as bool?) ?? true;
      await NotificationService.instance.runDailyDigest(
        warningDays: warningDays,
        notifyExpiry: notifExpiry,
        notifyLowStock: notifLow,
      );
    }
    return true;
  });
}

/// Configures the periodic daily background check.
class BackgroundWorker {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> scheduleDailyDigest({
    required int warningDays,
    required bool notifExpiry,
    required bool notifLowStock,
  }) async {
    await Workmanager().registerPeriodicTask(
      kDailyDigestTask,
      kDailyDigestTask,
      frequency: const Duration(hours: 24),
      initialDelay: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.notRequired),
      inputData: <String, dynamic>{
        'warningDays': warningDays,
        'notifExpiry': notifExpiry,
        'notifLowStock': notifLowStock,
      },
    );
  }

  static Future<void> cancel() async =>
      Workmanager().cancelByUniqueName(kDailyDigestTask);
}
