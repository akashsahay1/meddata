import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/domain/gst.dart';

/// Same vectors as backend/tests/Unit/GstMathTest.php: the bill screen's
/// preview and the server's invoice must agree to the paisa.
void main() {
  group('GST line maths (MRP includes GST)', () {
    // (mrp, qty, discount_bp, rate_bp, inter) => (discount, taxable, cgst, sgst, igst, total, rate)
    final Map<String, (List<Object>, List<int>)> vectors = <String, (List<Object>, List<int>)>{
      'intra 5%': (<Object>[3000, 2, 0, 500, false], <int>[0, 5714, 143, 143, 0, 6000, 2857]),
      'inter 5%': (<Object>[3000, 2, 0, 500, true], <int>[0, 5714, 0, 0, 286, 6000, 2857]),
      'intra 12% with 10% off':
          (<Object>[11250, 3, 1000, 1200, false], <int>[3375, 27121, 1627, 1627, 0, 30375, 9040]),
      'inter 12% with 10% off':
          (<Object>[11250, 3, 1000, 1200, true], <int>[3375, 27121, 0, 0, 3254, 30375, 9040]),
      'discount rounds down below half':
          (<Object>[105, 1, 500, 1200, false], <int>[5, 90, 5, 5, 0, 100, 90]),
      'discount rounds half up': (<Object>[105, 1, 1000, 1800, false], <int>[11, 80, 7, 7, 0, 94, 80]),
      'inter 18% with 2.5% off':
          (<Object>[4599, 7, 250, 1800, true], <int>[805, 26600, 0, 0, 4788, 31388, 3800]),
      'one paisa at 28%': (<Object>[1, 1, 0, 2800, false], <int>[0, 1, 0, 0, 0, 1, 1]),
      'nil rated': (<Object>[99999, 13, 0, 0, false], <int>[0, 1299987, 0, 0, 0, 1299987, 99999]),
      'free (100% off)': (<Object>[2050, 10, 10000, 1200, false], <int>[20500, 0, 0, 0, 0, 0, 0]),
      'odd discount': (<Object>[3333, 3, 333, 500, false], <int>[333, 9206, 230, 230, 0, 9666, 3069]),
      // MRP per strip of 15, qty in tablets: the line is priced as a whole.
      'strip of 15, two whole strips': (<Object>[3550, 30, 0, 1200, false, 15], <int>[0, 6340, 380, 380, 0, 7100, 3170]),
      'strip of 15, loose tablets': (<Object>[3550, 23, 0, 1200, false, 15], <int>[0, 4859, 292, 292, 0, 5443, 3169]),
      'strip of 15, 7 tablets inter-state': (<Object>[3550, 7, 0, 500, true, 15], <int>[0, 1578, 0, 0, 79, 1657, 3381]),
      'strip of 10 with 10% off': (<Object>[10550, 25, 1000, 1200, false, 10], <int>[2638, 21193, 1272, 1272, 0, 23737, 8477]),
    };

    vectors.forEach((String name, (List<Object>, List<int>) v) {
      test(name, () {
        final List<Object> i = v.$1;
        final GstLine l = GstMath.line(
          mrpPaise: i[0] as int,
          qty: i[1] as int,
          discountBp: i[2] as int,
          gstRateBp: i[3] as int,
          interState: i[4] as bool,
          packSize: i.length > 5 ? i[5] as int : 1,
        );
        expect(<int>[
          l.discountPaise, l.taxablePaise, l.cgstPaise, l.sgstPaise,
          l.igstPaise, l.totalPaise, l.ratePaise,
        ], v.$2);
        expect(l.taxablePaise + l.taxPaise, l.totalPaise,
            reason: 'taxable + tax is exactly what the customer pays');
        expect(l.grossPaise - l.discountPaise, l.totalPaise);
      });
    });
  });

  test('bill totals round to the nearest rupee', () {
    final GstTotals t = GstMath.totals(<GstLine>[
      GstMath.line(mrpPaise: 3000, qty: 2, gstRateBp: 500, interState: false),
      GstMath.line(mrpPaise: 11250, qty: 3, discountBp: 1000, gstRateBp: 1200, interState: false),
    ]);
    expect(<int>[
      t.subtotalPaise, t.discountPaise, t.taxablePaise, t.cgstPaise,
      t.sgstPaise, t.igstPaise, t.roundOffPaise, t.totalPaise,
    ], <int>[39750, 3375, 32835, 1770, 1770, 0, 25, 36400]);
  });

  test('round-off is half up', () {
    int roundOff(int net) => GstMath.totals(<GstLine>[
          GstLine(
              grossPaise: net,
              discountPaise: 0,
              ratePaise: net,
              taxablePaise: net,
              cgstPaise: 0,
              sgstPaise: 0,
              igstPaise: 0,
              totalPaise: net),
        ]).roundOffPaise;
    expect(<int>[roundOff(12349), roundOff(12350), roundOff(12399), roundOff(0)],
        <int>[-49, 50, 1, 0]);
    expect(GstMath.totals(const <GstLine>[]).totalPaise, 0);
  });

  test('financial year runs April to March', () {
    expect(GstMath.financialYear(DateTime(2026, 10, 5)), '26-27');
    expect(GstMath.financialYear(DateTime(2027, 3, 31, 23, 59)), '26-27');
    expect(GstMath.financialYear(DateTime(2027, 4, 1)), '27-28');
    expect(GstMath.financialYear(DateTime(2026, 1, 15)), '25-26');
    expect(GstMath.financialYear(DateTime(2099, 6, 1)), '99-00');
  });

  test('GSTIN check character and state', () {
    expect(Gstin.isValid('27AAPFU0939F1ZV'), isTrue);
    expect(Gstin.isValid('29AAGCB7383J1Z4'), isTrue);
    expect(Gstin.isValid('27AAPFU0939F1ZX'), isFalse, reason: 'wrong check character');
    expect(Gstin.isValid('27AAPFU0939F1Z'), isFalse);
    expect(Gstin.isValid('99AAPFU0939F1ZV'), isFalse, reason: 'not a state');
    expect(Gstin.normalize(' 27aapfu0939f1zv '), '27AAPFU0939F1ZV');
    expect(Gstin.stateOf('29AAGCB7383J1Z4'), '29');
    expect(GstStates.label('27'), '27 - Maharashtra');
    expect(GstStates.name('99'), isNull);
  });
}
