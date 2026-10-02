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
    'ML',
    'Tubes',
    'Sachets',
    'Injections',
    'Pieces',
    'Boxes',
  ];

  /// Maps a stored unit onto its [units] spelling, ignoring case, so records
  /// saved before a rename (e.g. 'ml' -> 'ML') still match the dropdown.
  static String canonicalUnit(String? unit) {
    final String u = (unit ?? '').trim();
    if (u.isEmpty) return 'Tablets';
    for (final String known in units) {
      if (known.toLowerCase() == u.toLowerCase()) return known;
    }
    return u;
  }

  /// Preset medicine categories. Customers pick from this fixed list rather
  /// than typing free text, so categorisation stays consistent.
  static const List<String> categories = <String>[
    'Uncategorised',
    'Pain Relief / Analgesic',
    'Antibiotic',
    'Antipyretic (Fever)',
    'Antacid / Gastro',
    'Cough & Cold',
    'Allergy / Antihistamine',
    'Diabetes',
    'Cardiac / Blood Pressure',
    'Vitamins & Supplements',
    'Dermatology / Skin',
    'Eye / Ear Drops',
    'Ayurvedic / Herbal',
    'First Aid',
    'Other',
  ];
}
