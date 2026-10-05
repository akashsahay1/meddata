import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/data/models/accounting.dart';
import 'package:med_stock/data/models/bill.dart';
import 'package:med_stock/domain/fefo.dart';
import 'package:med_stock/domain/gst.dart';
import 'package:med_stock/services/billing_api.dart';
import 'package:med_stock/state/bill_cart.dart';

void main() {
  final DateTime today = DateTime(2026, 10, 5);

  SaleBatch b(String id, String product, DateTime expiry, int qty,
          {int mrp = 3000, int version = 7, int? gst = 500, int discount = 0}) =>
      SaleBatch(
        id: id,
        productId: product,
        productName: product == 'dolo' ? 'Dolo 650' : 'Cough Syrup',
        unit: 'Strips',
        batchNo: id,
        expiryDate: expiry,
        mrpPaise: mrp,
        version: version,
        qty: qty,
        gstRateBp: gst,
        discountBp: discount,
      );

  final Map<String, List<SaleBatch>> stock = <String, List<SaleBatch>>{
    'dolo': <SaleBatch>[
      b('D2', 'dolo', DateTime(2027, 6, 30), 20, mrp: 3200),
      b('D1', 'dolo', DateTime(2026, 12, 31), 3),
      b('DX', 'dolo', DateTime(2026, 9, 30), 50),
    ],
    'syrup': <SaleBatch>[b('S1', 'syrup', DateTime(2027, 1, 31), 10, mrp: 11250, gst: null, discount: 1000)],
    'old': <SaleBatch>[b('O1', 'old', DateTime(2025, 1, 1), 5)],
    'none': <SaleBatch>[b('N1', 'none', DateTime(2027, 1, 1), 0)],
  };

  BillCart cart() => BillCart(
        loadBatches: (String id) async => stock[id] ?? const <SaleBatch>[],
        clock: () => today,
      )..shop = const ShopProfile(name: 'Sahay Medicals', stateCode: '27', gstin: '27AAPFU0939F1ZV', defaultGstRateBp: 1200);

  test('adding a medicine takes the earliest unexpired batch, spilling over', () async {
    final BillCart c = cart();
    expect(await c.addProduct('dolo'), AddOutcome.added);
    expect(await c.addProduct('dolo', qty: 4), AddOutcome.added, reason: 'same medicine adds up');
    expect(c.items.single.qty, 5);
    expect(c.lines.map((CartLine l) => (l.batch.id, l.qty, l.batch.mrpPaise)),
        <(String, int, int)>[('D1', 3, 3000), ('D2', 2, 3200)]);
    expect(c.available(c.items.single), 23, reason: 'the expired batch does not count');
    expect(c.totals.totalPaise, 9000 + 6400);

    expect(await c.addProduct('old'), AddOutcome.onlyExpired);
    expect(await c.addProduct('none'), AddOutcome.outOfStock);
    expect(await c.addProduct('missing'), AddOutcome.notFound);
    expect(c.items, hasLength(1));
  });

  test('tax uses the product rate or the shop default, and the customer state', () async {
    final BillCart c = cart();
    await c.addProduct('syrup');
    c.setQty(c.items.single, 3);
    // No product rate: the shop default (12%); the product's 10% discount.
    expect(c.lines.single.gstRateBp, 1200);
    expect(c.items.single.discountBp, 1000);
    GstTotals t = c.totals;
    expect(<int>[t.taxablePaise, t.cgstPaise, t.sgstPaise, t.igstPaise, t.totalPaise],
        <int>[27121, 1627, 1627, 0, 30400]);
    expect(c.isInterState, isFalse);

    c.update(() => c.customerGstin = '29aagcb7383j1z4');
    expect(c.placeOfSupply, '29');
    expect(c.isInterState, isTrue);
    t = c.totals;
    expect(<int>[t.taxablePaise, t.cgstPaise, t.igstPaise], <int>[27121, 0, 3254]);

    c.update(() => c.customerStateCode = '27');
    expect(c.isInterState, isFalse, reason: 'an explicit place of supply wins');
  });

  test('picking a batch, discounts and the request body', () async {
    final BillCart c = cart();
    await c.addProduct('dolo', qty: 2);
    final CartItem item = c.items.single;
    c.pinBatch(item, 'D2');
    c.setDiscount(item, 1000);
    c.update(() {
      c.paymentMode = PaymentMode.upi;
      c.customerName = ' Ramesh ';
      c.customerPhone = '98765 43210';
    });

    final Map<String, Object?> body = c.requestBody(deviceId: 'phone-1');
    expect(body['id'], c.billId);
    expect(body['payment_mode'], 'upi');
    expect(body['customer_name'], 'Ramesh');
    expect(body['customer_gstin'], isNull);
    expect(body['device_id'], 'phone-1');
    expect(body['lines'], <Map<String, Object?>>[
      <String, Object?>{'batch_id': 'D2', 'qty_units': 2, 'mrp_paise': 3200, 'batch_version': 7, 'discount_bp': 1000},
    ]);
  });

  test('what blocks a bill', () async {
    final BillCart c = cart();
    expect(c.problem(), 'Add at least one medicine.');
    await c.addProduct('dolo');
    expect(c.problem(), isNull);
    c.setQty(c.items.single, 30);
    expect(c.hasShortfall, isTrue);
    expect(c.problem(), contains('Only 23 Strips of Dolo 650'));
    c.setQty(c.items.single, 1);
    c.update(() => c.customerGstin = '27AAPFU0939F1ZX');
    expect(c.problem(), "The customer's GSTIN is not valid.");
    c.update(() {
      c.customerGstin = '';
      c.paymentMode = PaymentMode.credit;
    });
    // A credit bill goes on a customer's account; a typed name is not enough.
    c.update(() => c.customerName = 'Ramesh');
    expect(c.problem(), "Choose the customer's account for a credit bill.");
    c.setParty(const Party(
        id: 'p-1', type: PartyType.customer, name: 'Ramesh Kumar', phone: '9876543210', gstin: '29AABCU9603R1ZJ',
        stateCode: '29'));
    expect(c.problem(), isNull);
    // The party fills the customer fields and goes with the bill.
    expect((c.customerName, c.customerPhone, c.customerGstin, c.placeOfSupply), ('Ramesh Kumar', '9876543210', '29AABCU9603R1ZJ', '29'));
    expect(c.requestBody()['party_id'], 'p-1');
    c.reset();
    expect(c.party, isNull);
    expect(c.requestBody()['party_id'], isNull);
  });

  test('server answers: new prices, less stock, unsellable batches', () async {
    final BillCart c = cart();
    await c.addProduct('dolo', qty: 5);
    final String id = c.billId;

    // 409: D1 is now ₹31 (version 9).
    c.acceptPrices(const <StalePrice>[
      StalePrice(index: 0, batchId: 'D1', name: 'Dolo 650', batchNo: 'D1',
          sentMrpPaise: 3000, mrpPaise: 3100, version: 9, priceChanged: true),
    ]);
    expect(c.lines.first.batch.mrpPaise, 3100);
    expect(c.requestBody()['lines'], contains(containsPair('batch_version', 9)));

    // 422: only 1 left in D1 -> 4 from D2.
    c.applyStock(const <StockShort>[
      StockShort(batchId: 'D1', name: 'Dolo 650', batchNo: 'D1', requested: 3, available: 1),
    ]);
    expect(c.lines.map((CartLine l) => (l.batch.id, l.qty)), <(String, int)>[('D1', 1), ('D2', 4)]);

    // 422: D1 was deleted elsewhere.
    c.pinBatch(c.items.single, 'D1');
    c.dropBatches(<String>['D1']);
    expect(c.items.single.pinnedBatchId, isNull);
    expect(c.lines.map((CartLine l) => (l.batch.id, l.qty)), <(String, int)>[('D2', 5)]);
    expect(c.billId, id, reason: 'the same bill id until a bill is made');

    c.reset();
    expect(c.isEmpty, isTrue);
    expect(c.billId, isNot(id));
  });

  test('batches not yet synced are re-read before billing', () async {
    int version = 0;
    final BillCart c = BillCart(
      loadBatches: (String id) async =>
          <SaleBatch>[b('NEW', 'dolo', DateTime(2027), 4, version: version)],
      clock: () => today,
    );
    await c.addProduct('dolo');
    expect(c.hasUnsyncedBatches, isTrue);
    version = 12; // the sync gave it a server version
    await c.refreshUnsynced();
    expect(c.hasUnsyncedBatches, isFalse);
    expect(c.lines.single.batch.version, 12);
  });
}
