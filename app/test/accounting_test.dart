import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/data/models/accounting.dart';
import 'package:med_stock/data/models/bill.dart';
import 'package:med_stock/domain/accounting.dart';
import 'package:med_stock/domain/gst.dart';
import 'package:med_stock/domain/invoice_draft.dart';
import 'package:med_stock/domain/product_stock.dart';
import 'package:med_stock/data/models/medicine.dart';
import 'package:med_stock/services/accounting_api.dart';
import 'package:med_stock/services/accounting_pdf.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/invoice_pdf.dart';

import 'support/accounting_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('balances', () {
    test('in words: positive = to collect, negative = to pay', () {
      expect(BalanceText.of(120050), '₹1,200.50 to collect');
      expect(BalanceText.of(-5600000), '₹56,000.00 to pay');
      expect(BalanceText.of(0), 'Settled');
      expect(BalanceText.drCr(120050), '₹1,200.50 Dr');
      expect(BalanceText.drCr(-100), '₹1.00 Cr');
    });
  });

  group('GST maths for purchases (shared vector with backend GstMathTest)', () {
    test('tax is added on top of the rate', () {
      final GstLine l = GstMath.purchaseLine(ratePaise: 5000, qty: 10, discountBp: 1000, gstRateBp: 1200, interState: false);
      expect(<int>[l.grossPaise, l.discountPaise, l.taxablePaise, l.cgstPaise, l.sgstPaise, l.igstPaise, l.totalPaise],
          <int>[50000, 5000, 45000, 2700, 2700, 0, 50400]);
      final GstLine inter = GstMath.purchaseLine(ratePaise: 3333, qty: 3, discountBp: 500, gstRateBp: 1200, interState: true);
      expect(<int>[inter.grossPaise, inter.discountPaise, inter.taxablePaise, inter.igstPaise, inter.totalPaise],
          <int>[9999, 500, 9499, 1140, 10639]);
      final GstLine intra = GstMath.purchaseLine(ratePaise: 3333, qty: 3, discountBp: 500, gstRateBp: 1200, interState: false);
      expect(<int>[intra.cgstPaise, intra.sgstPaise, intra.totalPaise], <int>[570, 570, 10639]);
    });
  });

  group('returns', () {
    Bill bill() => Bill.fromJson(<String, dynamic>{
          'id': 'b-1',
          'invoice_no': 'MED/26-27/000001',
          'bill_date': '2026-10-05',
          'payment_mode': 'cash',
          'is_inter_state': false,
          'seller': <String, dynamic>{'name': 'Shop'},
          'items': <Object>[
            <String, dynamic>{'id': 1, 'name': 'Cough Syrup', 'qty_units': 3, 'mrp_paise': 11250, 'discount_bp': 1000,
              'gst_rate_bp': 1200, 'returned_qty': 1},
            <String, dynamic>{'id': 2, 'name': 'Dolo 650', 'qty_units': 2, 'mrp_paise': 3000, 'gst_rate_bp': 500, 'returned_qty': 2},
          ],
        });

    test('sale return: only what is left, same maths as the bill, request body', () {
      final Bill b = bill();
      expect(b.canReturn, isTrue);
      expect(b.items.first.returnableQty, 2);
      final ReturnDraft d = ReturnDraft.forBill(b);
      expect(d.lines.map((ReturnLine l) => (l.itemId, l.maxQty)), <(int, int)>[(1, 2)], reason: 'Dolo is fully returned');
      expect(d.isEmpty, isTrue);
      d.setQty(d.lines.single, 5);
      expect(d.lines.single.qty, 2, reason: 'clamped to what is left');
      d.setQty(d.lines.single, 1);
      // One syrup bottle: the server's vector (CN line 1 in ReturnApiTest).
      final GstLine g = d.gstOf(d.lines.single);
      expect(<int>[g.discountPaise, g.taxablePaise, g.cgstPaise, g.sgstPaise, g.totalPaise], <int>[1125, 9041, 542, 542, 10125]);
      expect(d.totals.totalPaise, 10100);
      expect(d.body(id: 'r-1', deviceId: 'phone', reason: ' Damaged ', refundMode: 'cash'), <String, Object?>{
        'id': 'r-1',
        'device_id': 'phone',
        'bill_id': 'b-1',
        'refund_mode': 'cash',
        'reason': 'Damaged',
        'lines': <Map<String, Object?>>[<String, Object?>{'bill_item_id': 1, 'qty_units': 1}],
      });
      d.all();
      expect(d.lines.single.qty, 2);
    });

    test('purchase return: billed qty less returns, purchase maths', () {
      final Purchase p = Purchase.fromJson(FakeAccountsServer.purchase());
      final ReturnDraft d = ReturnDraft.forPurchase(p);
      expect(d.isSale, isFalse);
      expect(d.lines.single.maxQty, 10, reason: '2 free packs are not returned on a debit note');
      d.setQty(d.lines.single, 1);
      expect(d.totals.totalPaise, 5000, reason: '₹45 + 12% = ₹50.40, rounded to ₹50');
      expect(d.body(id: 'x')['lines'], <Map<String, Object?>>[<String, Object?>{'purchase_item_id': 11, 'qty': 1}]);
      expect(d.body(id: 'x')['purchase_id'], 'pur-1');
      expect(d.body(id: 'x').containsKey('refund_mode'), isFalse);
    });
  });

  group('purchase from a scanned invoice', () {
    final ProductStock dolo = ProductStock.group(<Medicine>[
      Medicine(
        id: 'b-old',
        productId: 'prod-dolo',
        name: 'Dolo 650',
        unit: 'Tablets',
        quantity: 10,
        expiryDate: DateTime(2027),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]).single;

    test('known medicine by id, new medicine with its details; per-pack rates', () {
      final List<InvoiceDraftLine> lines = <InvoiceDraftLine>[
        InvoiceDraftLine(id: 'l0', name: 'DOLO 650 TAB', pack: "15's", batchNo: ' DB1 ', expiry: DateTime(2027, 6, 30),
            quantity: 2, freeQuantity: 1, mrp: 30.5, rate: 20.25, discountPercent: 2.5, gstPercent: 12, hsn: '3004',
            unit: 'Tablets', unitsPerPack: 15, product: dolo),
        InvoiceDraftLine(id: 'l1', name: 'Azithral 500', manufacturer: 'Alembic', pack: "5's", expiry: DateTime(2028, 3, 31),
            mfgDate: DateTime(2026, 4, 1), quantity: 4, mrp: 119.5, rate: 80, unit: 'Strips', barcode: '890123'),
      ];
      final Map<String, String> ids = <String, String>{};
      Map<String, Object?> build() => PurchaseFromInvoice.body(
            id: 'pur-x',
            partyId: 'p-1',
            invoiceNo: ' SG/1 ',
            invoiceDate: DateTime(2026, 10, 1),
            lines: lines,
            newProductId: (InvoiceDraftLine l) => ids.putIfAbsent(l.id, () => 'new-${ids.length}'),
            deviceId: 'phone',
            scanId: 9,
          );
      final Map<String, Object?> body = build();
      expect(<Object?>[body['id'], body['party_id'], body['supplier_invoice_no'], body['invoice_date'], body['invoice_scan_id']],
          <Object?>['pur-x', 'p-1', 'SG/1', '2026-10-01', 9]);
      final List<Map<String, Object?>> l = (body['lines']! as List<Object?>).cast<Map<String, Object?>>();
      expect(l[0], <String, Object?>{
        'product_id': 'prod-dolo',
        'batch_no': 'DB1',
        'expiry_date': '2027-06-30',
        'qty': 2,
        'free_qty': 1,
        'units_per_pack': 15,
        'rate_paise': 2025,
        'mrp_paise': 3050,
        'discount_bp': 250,
        'gst_rate_bp': 1200,
        'hsn': '3004',
      });
      expect(l[1]['product_id'], 'new-0');
      expect(l[1]['product'], <String, Object?>{
        'name': 'Azithral 500', 'manufacturer': 'Alembic', 'unit': 'Strips', 'pack_size': 1, 'category': 'Uncategorised',
        'barcode': '890123',
      });
      expect(<Object?>[l[1]['units_per_pack'], l[1]['mfg_date'], l[1].containsKey('gst_rate_bp'), l[1].containsKey('batch_no')],
          <Object?>[1, '2026-04-01', false, false]);
      // A retry sends the same new-medicine id (so it is created once).
      expect(((build()['lines']! as List<Object?>)[1]! as Map<String, Object?>)['product_id'], 'new-0');

      final GstTotals t = PurchaseFromInvoice.preview(lines, interState: false);
      // 2 x 20.25 less 2.5% = 39.49 (+12%) and 4 x 80 (+5% default).
      expect(t.taxablePaise, 3949 + 32000);
    });
  });

  group('GSTR CSV for the CA', () {
    test('GSTR-1 rows per section', () {
      final String csv = GstrCsv.gstr1(FakeAccountsServer.gstr1);
      final List<String> rows = const LineSplitter().convert(csv);
      expect(rows.first, contains('GSTR-1 summary,2026-10,GSTIN,27AAPFU0939F1ZV'));
      expect(rows[1], contains('for review by your CA'));
      expect(rows, contains('B2B,29AABCU9603R1ZJ,Lakshmi Clinic,MED/26-27/000002,2026-10-02,448.00,29,N,12,400.00,48.00,0.00,0.00'));
      expect(rows, contains('B2CS,OE,27,INTRA,5,1000.00,0.00,25.00,25.00'));
      expect(rows, contains('HSN,B2B,3004,Strips,4,12,448.00,400.00,48.00,0.00,0.00'));
      expect(rows, contains('DOCS,Invoices for outward supply,MED/26-27/000001,MED/26-27/000003,3,1,2'));
    });

    test('GSTR-3B summary rows', () {
      final List<String> rows = const LineSplitter().convert(GstrCsv.gstr3b(FakeAccountsServer.gstr3b));
      expect(rows, contains('3.1(a) Outward taxable supplies,1400.00,48.00,25.00,25.00'));
      expect(rows, contains('4(C) Net ITC,,0.00,27.00,27.00'));
      expect(rows, contains('Payable in cash,,46.00,0.00,0.00'));
    });

    test('months for the picker', () {
      final List<DateTime> m = recentMonths(DateTime(2026, 2, 10), count: 3);
      expect(m.map(monthKey), <String>['2026-02', '2026-01', '2025-12']);
    });
  });

  group('models', () {
    test('party, ledger, note and bill links parse', () {
      final Ledger l = Ledger.fromJson(<String, dynamic>{
        ...FakeAccountsServer.ledger,
        'party': partyJson('p-1', 'Ramesh', balance: 120000, gstin: '29AABCU9603R1ZJ'),
      });
      expect(l.party.stateLabel, '29 - Karnataka');
      expect(l.party.type.isCustomer, isTrue);
      expect(l.entries.map((LedgerEntry e) => (e.type, e.balancePaise)), <(String, int)>[('sale', 170000), ('payment_in', 120000)]);
      expect(l.entries.last.isPayment, isTrue);
      final ReturnNote n = ReturnNote.fromJson(FakeAccountsServer.note(credit: false));
      expect(<Object?>[n.isCreditNote, n.title, n.againstNo, n.taxSummary.single.rateBp], <Object?>[false, 'Debit note', 'PPD/42', 1200]);
      final Bill b = Bill.fromJson(<String, dynamic>{
        'id': 'b', 'party_id': 'p-1', 'status': 'cancelled', 'seller': <String, dynamic>{},
        'items': <Object>[<String, dynamic>{'id': 3, 'qty_units': 2}],
        'returns': <Object>[<String, dynamic>{'id': 'cn', 'note_no': 'CN/26-27/000004', 'return_date': '2026-10-05', 'total_paise': 500}],
      });
      expect(<Object?>[b.partyId, b.items.single.id, b.returns.single.noteNo, b.canReturn], <Object?>['p-1', 3, 'CN/26-27/000004', false]);
      expect(PartyType.from('both').isSupplier, isTrue);
      expect(MoneyMode.from('cheque').label, 'Cheque');
    });
  });

  group('AccountingApi', () {
    test('errors carry the server code; no answer means retry with the same id', () async {
      final List<http.Request> seen = <http.Request>[];
      int calls = 0;
      final AccountingApi api = AccountingApi(ApiClient(MockClient((http.Request r) async {
        seen.add(r);
        calls++;
        if (calls == 1) throw http.ClientException('offline');
        if (calls == 2) {
          return http.Response(
              jsonEncode(<String, Object?>{'message': 'Invoice X is already entered.', 'error': 'duplicate_invoice', 'purchase_id': 'p'}),
              422);
        }
        return http.Response(jsonEncode(<String, Object?>{'purchase': FakeAccountsServer.purchase(), 'replayed': true}), 200);
      })));
      final DocResult<Purchase> offline = await api.createPurchase('tok', <String, Object?>{'id': 'x'});
      expect(offline.isOffline, isTrue);
      final DocResult<Purchase> dup = await api.createPurchase('tok', <String, Object?>{'id': 'x'});
      expect(<Object?>[dup.isOk, dup.status, dup.error, dup.message, dup.body?['purchase_id']],
          <Object?>[false, 422, 'duplicate_invoice', 'Invoice X is already entered.', 'p']);
      final DocResult<Purchase> again = await api.createPurchase('tok', <String, Object?>{'id': 'x'});
      expect(<Object?>[again.isOk, again.replayed, again.value!.invoiceNo, again.value!.items.single.freeQty],
          <Object?>[true, true, 'PPD/42', 2]);
      expect(seen.last.headers['Authorization'], 'Bearer tok');
      expect(seen.last.url.path, endsWith('/purchases'));
    });

    test('lists and queries', () async {
      final FakeAccountsServer server = FakeAccountsServer();
      final ApiPage<Party> suppliers = (await server.api.parties('tok', type: 'supplier', query: 'pune')).value!;
      expect(suppliers.items.map((Party p) => p.name), <String>['Pune Pharma Distributors']);
      expect(server.requests.last.$2, <String, String>{'type': 'supplier', 'q': 'pune', 'page': '1', 'per_page': '50'});
      final ApiPage<PurchaseSummary> purchases = (await server.api.purchases('tok', from: DateTime(2026, 10))).value!;
      expect(<Object?>[purchases.totalPaise, purchases.count, purchases.hasMore], <Object?>[50400, 1, false]);
      expect(server.requests.last.$2?['from'], '2026-10-01');
      final Map<String, dynamic> r = (await server.api.gstReport('tok', '2026-10', gstr1: false)).value!;
      expect(r['return'], 'GSTR-3B');
    });
  });

  group('PDFs', () {
    test('ledger and credit note PDFs build with the invoice fonts', () async {
      final InvoiceFonts fonts = await InvoiceFonts.load();
      final Ledger l = Ledger.fromJson(<String, dynamic>{...FakeAccountsServer.ledger, 'party': partyJson('p', 'Ramesh Kumar')});
      final String ledger = latin1.decode(await AccountingPdf.ledger(l, fonts: fonts, compress: false));
      expect(ledger.startsWith('%PDF'), isTrue);
      expect(ledger, contains('Ledger Ramesh Kumar'), reason: 'document title');
      expect(ledger, contains('<20B9>'), reason: 'amounts print the rupee sign');
      expect(AccountingPdf.ledgerFileName(l), 'Ledger-Ramesh-Kumar.pdf');

      final ReturnNote n = ReturnNote.fromJson(FakeAccountsServer.note(credit: true));
      final String note = latin1.decode(await AccountingPdf.note(n, fonts: fonts, compress: false));
      expect(note, contains('Credit note CN/26-27/000001'));
      expect(AccountingPdf.noteFileName(n), 'Credit-note-CN-26-27-000001.pdf');
    });
  });
}
