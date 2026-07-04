/// App-wide constants. Keep values here so tuning is easy and consistent.
class AppConstants {
  AppConstants._();

  /// Free tier allows this many medicines. Enforced on add.
  static const int freeTierMedicineLimit = 7;

  /// Default number of days before expiry to start warning.
  static const int defaultExpiryWarningDays = 30;

  /// Default low-stock threshold applied to new medicines.
  static const int defaultLowStockThreshold = 10;

  /// Product IDs for Google Play Billing (used in a later phase).
  static const String productMonthly = 'premium_monthly';
  static const String productYearly = 'premium_yearly';
  static const String productLifetime = 'premium_lifetime';

  /// Common units for the medicine form.
  static const List<String> units = <String>[
    'Tablets',
    'Strips',
    'Capsules',
    'Bottles',
    'ml',
    'Tubes',
    'Sachets',
    'Injections',
    'Pieces',
    'Boxes',
  ];
}
