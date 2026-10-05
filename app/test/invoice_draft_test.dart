import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/domain/invoice_draft.dart';
import 'package:med_stock/domain/medicine_name_key.dart';
import 'package:med_stock/domain/product_stock.dart';

/// A shop medicine with one batch, as MedicineProvider.products has it.
ProductStock product(
  String id,
  String name, {
  String brand = '',
  String unit = 'Strips',
  String barcode = '',
}) {
  final DateTime t = DateTime(2026, 1, 1);
  return ProductStock(id, <Medicine>[
    Medicine(
      id: 'b-$id',
      productId: id,
      name: name,
      brand: brand,
      category: 'Pain Relief / Analgesic',
      barcode: barcode,
      unit: unit,
      quantity: 5,
      lowStockThreshold: 20,
      expiryDate: DateTime(2027, 1, 31),
      createdAt: t,
      updatedAt: t,
    ),
  ]);
}

/// One item as the server returns it (normalised), with overrides.
Map<String, dynamic> item(
  String name, [
  Map<String, dynamic> extra = const <String, dynamic>{},
]) => <String, dynamic>{
  'product_name': name,
  'manufacturer': null,
  'pack': "15's",
  'batch_no': 'B1',
  'expiry_date': '2027-06-30',
  'mfg_date': null,
  'quantity': 10,
  'free_quantity': 0,
  'mrp': 30.0,
  'purchase_rate': 20.0,
  'discount_percent': null,
  'gst_percent': 12.0,
  'hsn': null,
  'barcode': null,
  'match': <String, dynamic>{
    'product_id': null,
    'product_name': null,
    'master_id': null,
    'master_name': null,
    'master_manufacturer': null,
  },
  ...extra,
};

void main() {
  final DateTime now = DateTime(2026, 10, 5, 10);

  group('InvoiceDraftMapper.fromResult', () {
    test('maps the header and every product line, dropping nameless ones', () {
      final InvoiceDraft d = InvoiceDraftMapper.fromResult(<String, dynamic>{
        'supplier_name': 'Shree Ganesh Pharma',
        'supplier_gstin': '27ABCDE1234F1Z5',
        'invoice_no': 'SG/0456',
        'invoice_date': '2026-10-01',
        'notes': 'Line 3 is smudged.',
        'items': <Object?>[
          item('DOLO 650 TAB', <String, dynamic>{
            'manufacturer': 'MICRO',
            'batch_no': 'DOBS3975',
            'expiry_date': '2027-06-30',
            'mfg_date': '2025-07-01',
            'quantity': 10,
            'free_quantity': 2,
            'mrp': 30.91,
            'purchase_rate': '22.08',
            'discount_percent': 5,
          }),
          item(''),
          'not a line',
          item('CROCIN SYRUP', <String, dynamic>{
            'pack': '60ML',
            'batch_no': null,
            'expiry_date': '2027-02',
            'free_quantity': null,
            'mrp': '₹ 1,045.50',
          }),
        ],
      });

      expect(d.supplierName, 'Shree Ganesh Pharma');
      expect(d.supplierGstin, '27ABCDE1234F1Z5');
      expect(d.invoiceNo, 'SG/0456');
      expect(d.invoiceDate, DateTime(2026, 10, 1));
      expect(d.notes, 'Line 3 is smudged.');
      expect(d.lines.map((InvoiceDraftLine l) => l.id), <String>['l0', 'l1']);

      final InvoiceDraftLine dolo = d.lines[0];
      expect(dolo.name, 'DOLO 650 TAB');
      expect(dolo.manufacturer, 'MICRO');
      expect(dolo.batchNo, 'DOBS3975');
      expect(dolo.expiry, DateTime(2027, 6, 30));
      expect(dolo.mfgDate, DateTime(2025, 7, 1));
      expect(<num>[dolo.quantity, dolo.freeQuantity], <num>[10, 2]);
      expect(
        <num>[dolo.mrp, dolo.rate, dolo.discountPercent],
        <num>[30.91, 22.08, 5],
      );
      expect(dolo.gstPercent, 12);
      expect(dolo.unitsPerPack, 15);
      expect(dolo.unit, 'Strips');
      expect(dolo.isNewProduct, isTrue);

      final InvoiceDraftLine crocin = d.lines[1];
      expect(crocin.batchNo, '');
      expect(crocin.expiry, DateTime(2027, 2, 28)); // month only: end of month
      expect(crocin.freeQuantity, 0);
      expect(crocin.mrp, 1045.5);
      expect(crocin.unit, 'Bottles');
    });

    test('links lines to the shop medicine they most likely are', () {
      final List<ProductStock> shop = <ProductStock>[
        product('p-dolo', 'Dolo 650', brand: 'Micro Labs', unit: 'Tablets'),
        product('p-dolo-2', 'Dolo 650', brand: 'Other Pharma'),
        product('p-pan', 'Pan 40', barcode: '8901234567894'),
        product('p-crocin', 'Crocin Tab'),
        product('p-azee', 'Azee 500'),
      ];
      final InvoiceDraft d = InvoiceDraftMapper.fromResult(<String, dynamic>{
        'items': <Object?>[
          // Loose name match; the brand picks between two "Dolo 650"s.
          item('DOLO-650 TAB', <String, dynamic>{'manufacturer': 'MICRO'}),
          // Same barcode, different printed name.
          item('PANTOPRAZOLE 40', <String, dynamic>{
            'barcode': '8901234567894',
          }),
          // A syrup is not the shop's tablet.
          item('CROCIN SYRUP', <String, dynamic>{'pack': '60ML'}),
          // The server's suggestion wins when this device has the product.
          item('AZITHROMYCIN 500 (AZEE)', <String, dynamic>{
            'match': <String, dynamic>{'product_id': 'p-azee'},
          }),
          // A suggestion this device doesn't know is ignored.
          item('BRAND NEW 10', <String, dynamic>{
            'match': <String, dynamic>{'product_id': 'p-unknown'},
          }),
        ],
      }, products: shop);

      expect(
        d.lines.map((InvoiceDraftLine l) => l.target?.productId),
        <String?>['p-dolo', 'p-pan', null, 'p-azee', null],
      );
      // A batch of a known medicine is counted in that medicine's unit.
      expect(d.lines[0].stockUnit, 'Tablets');
      expect(d.lines[2].stockUnit, 'Bottles');
    });

    test('fills a missing manufacturer from the catalog match', () {
      final InvoiceDraft d = InvoiceDraftMapper.fromResult(<String, dynamic>{
        'items': <Object?>[
          item('AZITHRAL 500 TAB', <String, dynamic>{
            'match': <String, dynamic>{'master_manufacturer': 'Alembic Ltd'},
          }),
        ],
      });
      expect(d.lines.single.manufacturer, 'Alembic Ltd');
    });

    test('copes with an empty or odd result', () {
      expect(InvoiceDraftMapper.fromResult(<String, dynamic>{}).lines, isEmpty);
      final InvoiceDraft d = InvoiceDraftMapper.fromResult(<String, dynamic>{
        'items': <Object?>[
          item('X', <String, dynamic>{
            'quantity': 'lots',
            'mrp': null,
            'discount_percent': 250,
            'expiry_date': 'soon',
          }),
        ],
      });
      final InvoiceDraftLine l = d.lines.single;
      expect(<num>[l.quantity, l.mrp, l.discountPercent], <num>[0, 0, 100]);
      expect(l.expiry, isNull);
    });
  });

  group('InvoiceDraftLine', () {
    InvoiceDraftLine line({ProductStock? match, String unit = 'Strips'}) =>
        InvoiceDraftLine(
          id: 'l0',
          name: 'DOLO 650 TAB',
          manufacturer: 'MICRO',
          pack: "15's",
          batchNo: ' DOBS3975 ',
          expiry: DateTime(2027, 6, 30),
          quantity: 10,
          freeQuantity: 2,
          mrp: 30,
          rate: 20,
          discountPercent: 10,
          unit: unit,
          unitsPerPack: 15,
          product: match,
        );

    test('a new medicine counts packs as printed on the bill', () {
      final Medicine m = line().toMedicine(id: 'new-id', now: now);
      expect(m.id, 'new-id');
      expect(m.name, 'DOLO 650 TAB');
      expect(m.brand, 'MICRO');
      expect(m.category, 'Uncategorised');
      expect(m.batchNo, 'DOBS3975');
      expect(m.unit, 'Strips');
      expect(m.quantity, 12); // 10 billed + 2 free
      expect(m.sellingPrice, 30);
      expect(m.purchasePrice, 18); // rate after the 10% discount
      expect(m.expiryDate, DateTime(2027, 6, 30));
      expect(m.lowStockThreshold, 10);
    });

    test('a batch of a known medicine takes its name, brand and unit', () {
      final ProductStock dolo = product(
        'p-dolo',
        'Dolo 650',
        brand: 'Micro Labs',
        unit: 'Tablets',
      );
      final InvoiceDraftLine l = line(match: dolo);
      final Medicine m = l.toMedicine(id: 'b2', now: now);

      expect(
        <String>[m.name, m.brand, m.unit, m.category],
        <String>[
          'Dolo 650',
          'Micro Labs',
          'Tablets',
          'Pain Relief / Analgesic',
        ],
      );
      expect(m.lowStockThreshold, 20);
      // Counted per tablet: 12 strips of 15, prices per tablet.
      expect(l.countsPieces, isTrue);
      expect(m.quantity, 180);
      expect(m.sellingPrice, 2.0);
      expect(m.purchasePrice, 1.2);
    });

    test('HSN and GST% from the bill are saved on a new medicine', () {
      InvoiceDraftLine l(double? gst) => InvoiceDraftLine(
            id: 'l1',
            name: 'AZITHRAL 500',
            expiry: DateTime(2027, 6, 30),
            quantity: 3,
            mrp: 120,
            rate: 80,
            gstPercent: gst,
            hsn: ' 30042019 ',
            unit: 'Strips',
          );
      final Medicine m = l(12).toMedicine(id: 'n1', now: now);
      expect(m.hsn, '30042019');
      expect(m.gstRateBp, 1200);

      // 0% is a real rate; none / nonsense leaves the shop default.
      expect(l(0).toMedicine(id: 'n2', now: now).gstRateBp, 0);
      expect(l(2.5).gstRateBp, 250);
      expect(l(null).toMedicine(id: 'n3', now: now).gstRateBp, isNull);
      expect(l(140).gstRateBp, isNull);
    });

    test('a known medicine keeps its own HSN and GST rate', () {
      final ProductStock base = product('p-azi', 'Azithral 500');
      final Medicine first = base.first;
      final ProductStock withGst = ProductStock('p-azi', <Medicine>[
        first.copyWith(hsn: '3004', gstRateBp: 500),
      ]);
      InvoiceDraftLine l(ProductStock p) => InvoiceDraftLine(
            id: 'l2',
            name: 'AZITHRAL 500',
            expiry: DateTime(2027, 6, 30),
            quantity: 1,
            gstPercent: 12,
            hsn: '30042019',
            unit: 'Strips',
            product: p,
          );
      final Medicine kept = l(withGst).toMedicine(id: 'k', now: now);
      expect(<Object?>[kept.hsn, kept.gstRateBp], <Object?>['3004', 500]);
      // Without its own, the product takes the bill's.
      final Medicine filled = l(base).toMedicine(id: 'f', now: now);
      expect(<Object?>[filled.hsn, filled.gstRateBp], <Object?>['30042019', 1200]);
    });

    test('"add as a new medicine" ignores the match', () {
      final InvoiceDraftLine l = line(
        match: product('p-dolo', 'Dolo 650'),
      ).copyWith(asNew: true, unit: 'Strips');
      expect(l.target, isNull);
      expect(l.product?.productId, 'p-dolo'); // kept, so it can be undone
      expect(l.toMedicine(id: 'x', now: now).name, 'DOLO 650 TAB');
      expect(l.copyWith(asNew: false).target?.productId, 'p-dolo');
    });

    test('a pack count of one never multiplies', () {
      final InvoiceDraftLine l = line(
        unit: 'Tablets',
      ).copyWith(unitsPerPack: 1);
      expect(l.countsPieces, isFalse);
      expect(l.stockQuantity, 12);
    });

    test('lists what must be fixed and what is only worth a look', () {
      final InvoiceDraftLine ok = line();
      expect(ok.problems, isEmpty);
      expect(ok.isValid, isTrue);
      expect(ok.warnings(now), isEmpty);

      final InvoiceDraftLine bad = InvoiceDraftLine(
        id: 'l1',
        name: ' ',
        mfgDate: DateTime(2026, 1, 1),
      );
      expect(bad.problems, <String>[
        'Name missing',
        'Expiry date missing',
        'Quantity missing',
      ]);
      expect(bad.isValid, isFalse);
      expect(line().copyWith(mfgDate: DateTime(2027, 7, 1)).problems, <String>[
        'Expiry must be after the manufacture date',
      ]);
      expect(
        InvoiceDraftLine(
          id: 'l2',
          name: 'A',
          quantity: 1,
          expiry: DateTime(2026, 9, 30),
        ).warnings(now),
        <String>[
          'No batch number',
          'No MRP',
          'No purchase rate',
          'Already expired',
        ],
      );
    });
  });

  group('helpers', () {
    test('pieces per pack', () {
      expect(InvoiceDraftMapper.unitsPerPack("15's"), 15);
      expect(InvoiceDraftMapper.unitsPerPack('10S'), 10);
      expect(InvoiceDraftMapper.unitsPerPack('1x10'), 10);
      expect(InvoiceDraftMapper.unitsPerPack('10 X 10'), 100);
      expect(InvoiceDraftMapper.unitsPerPack('100ML'), 100);
      expect(InvoiceDraftMapper.unitsPerPack('30 gm'), 30);
      expect(InvoiceDraftMapper.unitsPerPack('20'), 20);
      expect(InvoiceDraftMapper.unitsPerPack(''), 1);
      expect(InvoiceDraftMapper.unitsPerPack('TUBE'), 1);
    });

    test('unit of a new medicine', () {
      expect(InvoiceDraftMapper.guessUnit('DOLO 650 TAB', "15's"), 'Strips');
      expect(InvoiceDraftMapper.guessUnit('MOX 500', '1x10'), 'Strips');
      expect(InvoiceDraftMapper.guessUnit('BENADRYL', '100ML'), 'Bottles');
      expect(InvoiceDraftMapper.guessUnit('CROCIN SYRUP', ''), 'Bottles');
      expect(
        InvoiceDraftMapper.guessUnit('MONOCEF 1G INJ', '1 VIAL'),
        'Injections',
      );
      expect(InvoiceDraftMapper.guessUnit('VOLINI GEL', '30GM'), 'Tubes');
      expect(
        InvoiceDraftMapper.guessUnit('ELECTRAL POWDER', '21GM'),
        'Sachets',
      );
      expect(InvoiceDraftMapper.guessUnit('BANDAGE ROLL', ''), 'Pieces');
    });

    test('dates', () {
      expect(InvoiceDraftMapper.parseDate('2027-06-15'), DateTime(2027, 6, 15));
      expect(
        InvoiceDraftMapper.parseDate('2028-02', endOfMonth: true),
        DateTime(2028, 2, 29),
      );
      expect(InvoiceDraftMapper.parseDate('2028-02'), DateTime(2028, 2, 1));
      expect(InvoiceDraftMapper.parseDate('2027-02-30'), isNull);
      expect(InvoiceDraftMapper.parseDate('1999-01-01'), isNull);
      expect(InvoiceDraftMapper.parseDate(null), isNull);
    });

    test('medicine names match loosely but not across dosage forms', () {
      expect(MedicineNameKey.same("DOLO-650 TAB 15'S", 'Dolo 650'), isTrue);
      expect(MedicineNameKey.same('PAN 40MG TAB', 'Pan 40'), isTrue);
      expect(
        MedicineNameKey.same(
          'AUGMENTIN DUO 625 TAB 1X10',
          'Augmentin 625 Duo Tablet',
        ),
        isTrue,
      );
      expect(MedicineNameKey.same('Alprax 0.25', 'ALPRAX 0.25 TAB'), isTrue);
      expect(MedicineNameKey.same('Crocin Syrup', 'Crocin Tab'), isFalse);
      expect(MedicineNameKey.same('Dolo 650', 'Dolo 500'), isFalse);
      expect(MedicineNameKey.same('Alprax 0.25', 'Alprax 0.5'), isFalse);
      expect(MedicineNameKey.same('', ''), isFalse);
    });
  });
}
