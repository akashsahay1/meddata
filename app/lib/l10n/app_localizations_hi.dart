// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'दवा स्टॉक';

  @override
  String get addMedicine => 'दवा जोड़ें';

  @override
  String get totalMedicines => 'कुल दवाइयाँ';

  @override
  String get expiringSoon => 'जल्द समाप्त';

  @override
  String get expired => 'समाप्त';

  @override
  String get lowStock => 'कम स्टॉक';

  @override
  String get searchHint => 'नाम, बैच या बारकोड खोजें';

  @override
  String get all => 'सभी';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get alerts => 'अलर्ट';

  @override
  String get reports => 'रिपोर्ट';

  @override
  String get upgrade => 'अपग्रेड';

  @override
  String freePlanCount(int count, int limit) {
    return 'मुफ़्त प्लान — $count / $limit दवाइयाँ';
  }

  @override
  String get noMedicinesYet => 'अभी कोई दवा नहीं';

  @override
  String get subscribe => 'सदस्यता लें';

  @override
  String get restorePurchases => 'खरीद पुनर्स्थापित करें';
}
