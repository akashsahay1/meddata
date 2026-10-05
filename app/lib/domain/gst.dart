/// GST arithmetic for bills, in integer paise. Shop prices are MRPs, which
/// include GST, so tax is taken out of the amount rather than added on.
///
/// Mirrors backend/app/Support/GstMath.php exactly (same rounding, same
/// test vectors) so the bill screen's preview matches the invoice; the
/// server's numbers are the ones that count.
///
/// Per line:
///   gross    = mrp x qty
///   discount = gross x discount% (rounded half up)
///   amount   = gross - discount            what the customer pays for it
///   inter-state: taxable = amount x 100 / (100 + rate%), IGST = the rest
///   intra-state: CGST = SGST = amount x (rate%/2) / (100 + rate%),
///                taxable = amount - CGST - SGST
/// The bill total is rounded to the nearest rupee (50 paise rounds up).
class GstMath {
  GstMath._();

  /// n / d rounded half up, for n >= 0 and d > 0.
  static int roundDiv(int n, int d) => (2 * n + d) ~/ (2 * d);

  static GstLine line({
    required int mrpPaise,
    required int qty,
    int discountBp = 0,
    required int gstRateBp,
    required bool interState,
  }) {
    final int gross = mrpPaise * qty;
    final int discount = roundDiv(gross * discountBp, 10000);
    final int amount = gross - discount;
    final int taxable;
    int cgst = 0, sgst = 0, igst = 0;
    if (interState) {
      taxable = roundDiv(amount * 10000, 10000 + gstRateBp);
      igst = amount - taxable;
    } else {
      cgst = sgst = roundDiv(amount * gstRateBp, 2 * (10000 + gstRateBp));
      taxable = amount - cgst - sgst;
    }
    return GstLine(
      grossPaise: gross,
      discountPaise: discount,
      ratePaise: qty > 0 ? roundDiv(taxable, qty) : 0,
      taxablePaise: taxable,
      cgstPaise: cgst,
      sgstPaise: sgst,
      igstPaise: igst,
      totalPaise: amount,
    );
  }

  static GstTotals totals(Iterable<GstLine> lines) {
    int gross = 0, discount = 0, taxable = 0, cgst = 0, sgst = 0, igst = 0, net = 0;
    for (final GstLine l in lines) {
      gross += l.grossPaise;
      discount += l.discountPaise;
      taxable += l.taxablePaise;
      cgst += l.cgstPaise;
      sgst += l.sgstPaise;
      igst += l.igstPaise;
      net += l.totalPaise;
    }
    final int roundOff = roundDiv(net, 100) * 100 - net;
    return GstTotals(
      subtotalPaise: gross,
      discountPaise: discount,
      taxablePaise: taxable,
      cgstPaise: cgst,
      sgstPaise: sgst,
      igstPaise: igst,
      roundOffPaise: roundOff,
      totalPaise: net + roundOff,
    );
  }

  /// Indian financial year (1 April - 31 March) of a date, e.g. "26-27".
  static String financialYear(DateTime d) {
    final int start = d.month >= 4 ? d.year : d.year - 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return '${two(start)}-${two(start + 1)}';
  }
}

class GstLine {
  const GstLine({
    required this.grossPaise,
    required this.discountPaise,
    required this.ratePaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalPaise,
  });

  /// MRP x qty, before discount.
  final int grossPaise;
  final int discountPaise;

  /// Unit price before GST, after discount (display only).
  final int ratePaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;

  /// Taxable value + tax: what the customer pays for the line.
  final int totalPaise;

  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

class GstTotals {
  const GstTotals({
    required this.subtotalPaise,
    required this.discountPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.roundOffPaise,
    required this.totalPaise,
  });

  static const GstTotals zero = GstTotals(
      subtotalPaise: 0,
      discountPaise: 0,
      taxablePaise: 0,
      cgstPaise: 0,
      sgstPaise: 0,
      igstPaise: 0,
      roundOffPaise: 0,
      totalPaise: 0);

  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;

  /// -49..+50 paise, so [totalPaise] is a whole number of rupees.
  final int roundOffPaise;
  final int totalPaise;

  int get taxPaise => cgstPaise + sgstPaise + igstPaise;
}

/// GST state / union territory codes (the first two digits of a GSTIN).
class GstStates {
  GstStates._();

  static const Map<String, String> all = <String, String>{
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman and Diu',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (before 2014)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
  };

  static String? name(String? code) => code == null ? null : all[code];

  /// "27 - Maharashtra", or just the code if unknown.
  static String label(String code) {
    final String? n = all[code];
    return n == null ? code : '$code - $n';
  }
}

/// GSTIN checks: state code, PAN, entity number, 'Z', check character.
class Gstin {
  Gstin._();

  static const String _chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static final RegExp _format =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  /// Upper-cased, spaces removed.
  static String normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'\s'), '');

  static bool isValid(String gstin) {
    if (!_format.hasMatch(gstin)) return false;
    if (!GstStates.all.containsKey(gstin.substring(0, 2))) return false;
    return gstin[14] == checkChar(gstin.substring(0, 14));
  }

  /// The state code a (valid-looking) GSTIN belongs to.
  static String? stateOf(String gstin) =>
      gstin.length >= 2 && GstStates.all.containsKey(gstin.substring(0, 2))
          ? gstin.substring(0, 2)
          : null;

  /// GSTIN check character (weights 1,2,1,2,... in base 36).
  static String checkChar(String first14) {
    int sum = 0;
    for (int i = 0; i < 14; i++) {
      final int product = _chars.indexOf(first14[i]) * (i.isEven ? 1 : 2);
      sum += product ~/ 36 + product % 36;
    }
    return _chars[(36 - sum % 36) % 36];
  }
}
