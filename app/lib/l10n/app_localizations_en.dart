// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Medicine Stock';

  @override
  String get addMedicine => 'Add Medicine';

  @override
  String get totalMedicines => 'Total Medicines';

  @override
  String get expiringSoon => 'Expiring Soon';

  @override
  String get expired => 'Expired';

  @override
  String get lowStock => 'Low Stock';

  @override
  String get searchHint => 'Search name, batch or barcode';

  @override
  String get all => 'All';

  @override
  String get settings => 'Settings';

  @override
  String get alerts => 'Alerts';

  @override
  String get reports => 'Reports';

  @override
  String get upgrade => 'UPGRADE';

  @override
  String freePlanCount(int count, int limit) {
    return 'Free plan — $count / $limit medicines';
  }

  @override
  String get noMedicinesYet => 'No medicines yet';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get restorePurchases => 'Restore purchases';
}
