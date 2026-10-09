import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the lock re-checks itself the moment the trial runs out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService s = SettingsService();
    await s.init();
    addTearDown(s.dispose);

    await s.setTrialEndsAt(DateTime.now().add(const Duration(milliseconds: 300)));
    expect(s.hasAccess, isTrue);

    int notified = 0;
    s.addListener(() => notified++);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(notified, greaterThanOrEqualTo(1),
        reason: 'listeners (the root gate) hear about the trial ending');
    expect(s.hasAccess, isFalse);
  });

  test('a trial ending in days arms no timer yet; the hourly re-check does', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService s = SettingsService();
    await s.init();
    addTearDown(s.dispose);
    await s.setTrialEndsAt(DateTime.now().add(const Duration(days: 5)));
    int notified = 0;
    s.addListener(() => notified++);
    s.recheckTrialEnd();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(notified, 0);
    expect(s.hasAccess, isTrue);
  });

  test('a trial already over, or none, arms no timer and keeps quiet', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService s = SettingsService();
    await s.init();
    addTearDown(s.dispose);
    await s.setTrialEndsAt(DateTime.now().subtract(const Duration(days: 1)));
    int notified = 0;
    s.addListener(() => notified++);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(notified, 0);
    expect(s.hasAccess, isFalse);
  });
}
