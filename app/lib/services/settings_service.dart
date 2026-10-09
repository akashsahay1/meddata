import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Persists lightweight user preferences and cached entitlement.
class SettingsService extends ChangeNotifier {
  static const String _kThemeMode = 'theme_mode';
  static const String _kWarningDays = 'expiry_warning_days';
  static const String _kReminderHour = 'reminder_hour';
  static const String _kReminderMinute = 'reminder_minute';
  static const String _kNotifExpiry = 'notif_expiry_enabled';
  static const String _kNotifLowStock = 'notif_low_stock_enabled';
  static const String _kOnboarded = 'onboarded';
  static const String _kPremium = 'cached_premium';
  static const String _kTrialEndsAt = 'trial_ends_at';
  static const String _kCurrency = 'currency_symbol';
  static const String _kLocale = 'locale_code';

  late SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  int _warningDays = AppConstants.defaultExpiryWarningDays;
  int _reminderHour = 9;
  int _reminderMinute = 0;
  bool _notifExpiry = true;
  bool _notifLowStock = true;
  bool _onboarded = false;
  bool _premium = false;
  DateTime? _trialEndsAt;
  String _currency = '₹';
  String _localeCode = 'en';

  ThemeMode get themeMode => _themeMode;
  int get warningDays => _warningDays;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
  TimeOfDay get reminderTime =>
      TimeOfDay(hour: _reminderHour, minute: _reminderMinute);
  bool get notifExpiry => _notifExpiry;
  bool get notifLowStock => _notifLowStock;
  bool get onboarded => _onboarded;
  bool get isPremium => _premium;
  DateTime? get trialEndsAt => _trialEndsAt;
  String get currency => _currency;
  String get localeCode => _localeCode;
  /// India: dates read day/month/year (date pickers, typed dates).
  Locale get locale => Locale(_localeCode, 'IN');

  /// The app's languages, as Indian locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en', 'IN'),
    Locale('hi', 'IN'),
  ];

  /// Whether the free trial is currently active.
  bool get isTrialActive =>
      _trialEndsAt != null && _trialEndsAt!.isAfter(DateTime.now());

  /// Days remaining in the trial (0 if none / expired).
  /// Calendar days until the trial's end date (so a 7-day trial reads 7 and a
  /// few minutes of clock drift can't make it 8); 1 on the last day, 0 after.
  int get trialDaysLeft {
    final DateTime? end = _trialEndsAt;
    final DateTime now = DateTime.now();
    if (end == null || !end.isAfter(now)) return 0;
    // Rounded so a DST shift between the two midnights can't drop a day.
    final int d = (DateTime(end.year, end.month, end.day)
                .difference(DateTime(now.year, now.month, now.day))
                .inHours /
            24)
        .round();
    return d < 1 ? 1 : d;
  }

  /// The app is usable if the user has paid premium OR is within the trial.
  /// Otherwise the app is locked behind the subscribe paywall.
  bool get hasAccess => _premium || isTrialActive;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[_prefs.getInt(_kThemeMode) ?? 0];
    _warningDays =
        _prefs.getInt(_kWarningDays) ?? AppConstants.defaultExpiryWarningDays;
    _reminderHour = _prefs.getInt(_kReminderHour) ?? 9;
    _reminderMinute = _prefs.getInt(_kReminderMinute) ?? 0;
    _notifExpiry = _prefs.getBool(_kNotifExpiry) ?? true;
    _notifLowStock = _prefs.getBool(_kNotifLowStock) ?? true;
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _premium = _prefs.getBool(_kPremium) ?? false;
    final int? trialMs = _prefs.getInt(_kTrialEndsAt);
    _trialEndsAt =
        trialMs == null ? null : DateTime.fromMillisecondsSinceEpoch(trialMs);
    _watchTrialEnd();
    _currency = _prefs.getString(_kCurrency) ?? '₹';
    _localeCode = _prefs.getString(_kLocale) ?? 'en';
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setWarningDays(int days) async {
    _warningDays = days;
    await _prefs.setInt(_kWarningDays, days);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay t) async {
    _reminderHour = t.hour;
    _reminderMinute = t.minute;
    await _prefs.setInt(_kReminderHour, t.hour);
    await _prefs.setInt(_kReminderMinute, t.minute);
    notifyListeners();
  }

  Future<void> setNotifExpiry(bool v) async {
    _notifExpiry = v;
    await _prefs.setBool(_kNotifExpiry, v);
    notifyListeners();
  }

  Future<void> setNotifLowStock(bool v) async {
    _notifLowStock = v;
    await _prefs.setBool(_kNotifLowStock, v);
    notifyListeners();
  }

  Future<void> setOnboarded(bool v) async {
    _onboarded = v;
    await _prefs.setBool(_kOnboarded, v);
    notifyListeners();
  }

  Future<void> setPremium(bool v) async {
    _premium = v;
    await _prefs.setBool(_kPremium, v);
    notifyListeners();
  }

  /// Fires when the trial runs out, so the lock screen shows at that
  /// moment on a PC left open all day, not at the next restart.
  Timer? _trialEndTimer;

  /// Arms [_trialEndTimer] once the trial has under a day left; the app's
  /// hourly tick calls this again, so a later end is picked up in time.
  void recheckTrialEnd() => _watchTrialEnd();

  void _watchTrialEnd() {
    _trialEndTimer?.cancel();
    _trialEndTimer = null;
    final DateTime? end = _trialEndsAt;
    if (end == null) return;
    final Duration left = end.difference(DateTime.now());
    if (left.isNegative || left > const Duration(days: 1)) return;
    _trialEndTimer = Timer(left + const Duration(seconds: 1), notifyListeners);
  }

  @override
  void dispose() {
    _trialEndTimer?.cancel();
    super.dispose();
  }

  Future<void> setTrialEndsAt(DateTime? when) async {
    _trialEndsAt = when;
    _watchTrialEnd();
    if (when == null) {
      await _prefs.remove(_kTrialEndsAt);
    } else {
      await _prefs.setInt(_kTrialEndsAt, when.millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  Future<void> setCurrency(String symbol) async {
    _currency = symbol;
    await _prefs.setString(_kCurrency, symbol);
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    _localeCode = code;
    await _prefs.setString(_kLocale, code);
    notifyListeners();
  }
}
