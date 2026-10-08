/// Units counted per piece of a pack (stock and prices per tablet, capsule
/// or ml). Every other unit counts whole packs (strips, bottles, tubes...).
const Set<String> kPieceUnits = <String>{'Tablets', 'Capsules', 'ML'};

/// How many pieces one pack of a medicine holds: a strip of 6 tablets, a
/// strip of 1, a bottle of 100 ml. Stock is always stored in pieces; the
/// pack size lets it be entered and read as packs + loose pieces, and lets
/// a bill say "2 strips + 3 tablets". A product counted in whole packs
/// (unit Strips, Bottles...) keeps its pack size but nothing uses it.
class PackSize {
  PackSize._();

  static const int max = 10000;

  /// Whether [packSize] splits stock of [unit] into packs and loose pieces.
  static bool applies(String unit, int packSize) =>
      packSize > 1 && kPieceUnits.contains(unit);

  /// What one pack of this unit is called.
  static String packNoun(String unit) => unit == 'ML' ? 'bottle' : 'strip';

  /// What one piece of this unit is called.
  static String pieceNoun(String unit) {
    switch (unit) {
      case 'Tablets':
        return 'tablet';
      case 'Capsules':
        return 'capsule';
      case 'ML':
        return 'ml';
      default:
        return unit.toLowerCase();
    }
  }

  /// Label of the pack-size field: "Tablets per strip", "ML per bottle".
  static String perPackLabel(String unit) => '$unit per ${packNoun(unit)}';

  /// Packs and loose pieces in [units].
  static (int packs, int loose) split(int units, int packSize) =>
      packSize > 1 ? (units ~/ packSize, units % packSize) : (0, units);

  /// [units] as packs + loose pieces: "2 strips + 3 tablets", "2 strips",
  /// "3 tablets". Empty when the pack size doesn't apply to [unit].
  static String breakdown(int units, String unit, int packSize) {
    if (!applies(unit, packSize) || units < 0) return '';
    final (int packs, int loose) = split(units, packSize);
    final String pieces = '$loose ${_plural(loose, pieceNoun(unit))}';
    if (packs == 0) return pieces;
    final String whole = '$packs ${_plural(packs, packNoun(unit))}';
    return loose == 0 ? whole : '$whole + $pieces';
  }

  /// Stock as read on a card: "23 Tablets (2 strips + 3 tablets)" when the
  /// pack size applies, else "23 Tablets".
  static String stock(int units, String unit, int packSize) {
    final String b = breakdown(units, unit, packSize);
    return b.isEmpty ? '$units $unit' : '$units $unit ($b)';
  }

  static String _plural(int n, String noun) =>
      n == 1 || noun == 'ml' ? noun : '${noun}s';

  /// Pieces in one pack from a printed label: "15's" → 15, "1x10" → 10,
  /// "100ML" → 100, "strip of 10 tablets" → 10, "10" → 10; 1 when the
  /// label doesn't say.
  static int parse(String label) {
    final String p = label.toLowerCase();
    int clamp(num n) => n.round().clamp(1, max).toInt();
    final RegExpMatch? times =
        RegExp(r'(\d{1,4})\s*[x×*]\s*(\d{1,4})').firstMatch(p);
    if (times != null) {
      return clamp(int.parse(times[1]!) * int.parse(times[2]!));
    }
    final RegExpMatch? count =
        RegExp(r"(\d{1,4})\s*['’`]?\s*s\b").firstMatch(p);
    if (count != null) return clamp(int.parse(count[1]!));
    final RegExpMatch? measure = RegExp(
      r'(\d{1,5}(?:\.\d+)?)\s*(ml|gm|g|tab(?:let)?s?|cap(?:sule)?s?|nos?)\b',
    ).firstMatch(p);
    if (measure != null) return clamp(double.parse(measure[1]!));
    final RegExpMatch? plain = RegExp(r'^\s*(\d{1,4})\s*$').firstMatch(p);
    if (plain != null) return clamp(int.parse(plain[1]!));
    return 1;
  }
}
