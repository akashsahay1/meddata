/// Loose comparison of a medicine name as printed on a supplier invoice with
/// the name a shop typed ("DOLO-650 TAB 15'S" vs "Dolo 650"). Case, word
/// order, punctuation, "mg", strip counts ("15's", "1x10") and dosage-form
/// spellings (tab/tablet, syp/syrup, ...) don't matter. A dosage form is only
/// ignored when one of the two names has none, so "Crocin Syrup" never
/// matches "Crocin Tab". Same rules as the server
/// (backend/app/Support/MedicineNameKey.php).
class MedicineNameKey {
  const MedicineNameKey._(this.key, this.base, this.hasForm);

  factory MedicineNameKey.of(String name) {
    final List<String> tokens = MedicineNameKey.tokens(name);
    final List<String> base =
        tokens.where((String t) => !_formTokens.contains(t)).toList()..sort();
    tokens.sort();
    return MedicineNameKey._(
      tokens.join(' '),
      base.join(' '),
      base.length != tokens.length,
    );
  }

  /// Sorted canonical tokens, e.g. "650 dolo tab".
  final String key;

  /// [key] without dosage forms, e.g. "650 dolo".
  final String base;
  final bool hasForm;

  static const Map<String, String> _forms = <String, String>{
    'tab': 'tab',
    'tabs': 'tab',
    'tablet': 'tab',
    'tablets': 'tab',
    'cap': 'cap',
    'caps': 'cap',
    'capsule': 'cap',
    'capsules': 'cap',
    'syp': 'syp',
    'syr': 'syp',
    'syrup': 'syp',
    'susp': 'susp',
    'suspension': 'susp',
    'inj': 'inj',
    'injection': 'inj',
    'vial': 'inj',
    'amp': 'inj',
    'ampoule': 'inj',
    'oint': 'oint',
    'ointment': 'oint',
    'cream': 'cream',
    'crm': 'cream',
    'gel': 'gel',
    'drop': 'drops',
    'drops': 'drops',
    'lotion': 'lotion',
    'sachet': 'sachet',
    'sachets': 'sachet',
    'powder': 'powder',
    'pdr': 'powder',
    'sol': 'sol',
    'solution': 'sol',
  };
  static final Set<String> _formTokens = _forms.values.toSet();
  static final RegExp _token = RegExp(r'[a-z]+|\d+(?:\.\d+)?');
  static final RegExp _number = RegExp(r'^\d+(?:\.\d+)?$');
  static final RegExp _integer = RegExp(r'^\d+$');

  /// Canonical tokens in printed order: letters and numbers split apart,
  /// "mg" and pack counts dropped, dosage forms canonicalised.
  static List<String> tokens(String name) {
    final List<String> raw = _token
        .allMatches(name.toLowerCase())
        .map((RegExpMatch m) => m[0]!)
        .toList();
    final List<String> out = <String>[];
    for (int i = 0; i < raw.length; i++) {
      final String t = raw[i];
      final String? next = i + 1 < raw.length ? raw[i + 1] : null;
      final bool isNumber = _number.hasMatch(t);
      if (isNumber && next == 's') {
        i++; // 15's, 10s
        continue;
      }
      if (isNumber &&
          next == 'x' &&
          i + 2 < raw.length &&
          _integer.hasMatch(raw[i + 2])) {
        i += 2; // 1x10, 10 x 10
        continue;
      }
      if (t == 'mg') continue;
      out.add(_forms[t] ?? t);
    }
    return out;
  }

  /// Whether the two names most likely mean the same medicine.
  bool matches(MedicineNameKey other) {
    if (key.isEmpty) return false;
    if (key == other.key) return true;
    return base.isNotEmpty &&
        base == other.base &&
        (!hasForm || !other.hasForm);
  }

  static bool same(String a, String b) =>
      MedicineNameKey.of(a).matches(MedicineNameKey.of(b));
}
