import 'package:flutter_test/flutter_test.dart';
import 'package:medikabiz/data/models/bill.dart';
import 'package:medikabiz/services/api_client.dart';
import 'package:medikabiz/services/billing_api.dart';
import 'package:medikabiz/services/invoice_share.dart';

/// A server bill as POST /bills returns it.
Map<String, dynamic> sampleBill({String status = 'final', String? phone = '98765 43210'}) => <String, dynamic>{
      'id': '0b0c3f9e-1111-4a5b-9c1d-000000000001',
      'invoice_no': 'MED/26-27/000042',
      'fy': '26-27',
      'seq': 42,
      'bill_date': '2026-10-05',
      'created_at': '2026-10-05T11:30:00+05:30',
      'status': status,
      'payment_mode': 'upi',
      'customer_name': 'City Clinic',
      'customer_phone': phone,
      'customer_gstin': '29AAGCB7383J1Z4',
      'customer_state_code': '29',
      'customer_address': 'MG Road, Bengaluru',
      'place_of_supply': '29',
      'place_of_supply_name': 'Karnataka',
      'is_inter_state': true,
      'seller': <String, dynamic>{
        'name': 'Sahay Medicals',
        'legal_name': 'Sahay Medicals Pvt Ltd',
        'address': '12 Station Road, Pune',
        'phone': '020 1234567',
        'gstin': '27AAPFU0939F1ZV',
        'state_code': '27',
        'drug_license_no': 'MH-20B-12345',
      },
      'subtotal_paise': 39750,
      'discount_paise': 3375,
      'taxable_paise': 32835,
      'cgst_paise': 0,
      'sgst_paise': 0,
      'igst_paise': 3540,
      'round_off_paise': 25,
      'total_paise': 36400,
      'cancelled_at': null,
      'cancel_reason': null,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'line_no': 1, 'product_id': 'p1', 'batch_id': 'b1', 'name': 'Dolo 650', 'hsn': '3004',
          'unit': 'Tablets', 'pack_size': 15, 'batch_no': 'B1', 'expiry_date': '2027-10-31', 'qty_units': 2,
          'mrp_paise': 3000, 'rate_paise': 2857, 'discount_bp': 0, 'discount_paise': 0,
          'gst_rate_bp': 500, 'taxable_paise': 5714, 'cgst_paise': 0, 'sgst_paise': 0,
          'igst_paise': 286, 'total_paise': 6000,
        },
        <String, dynamic>{
          'line_no': 2, 'product_id': 'p2', 'batch_id': 'b2', 'name': 'Cough Syrup', 'hsn': '3004',
          'unit': 'Bottles', 'batch_no': 'S9', 'expiry_date': '2027-01-31', 'qty_units': 3,
          'mrp_paise': 11250, 'rate_paise': 9040, 'discount_bp': 1000, 'discount_paise': 3375,
          'gst_rate_bp': 1200, 'taxable_paise': 27121, 'cgst_paise': 0, 'sgst_paise': 0,
          'igst_paise': 3254, 'total_paise': 30375,
        },
      ],
      'tax_summary': <Map<String, dynamic>>[
        <String, dynamic>{'gst_rate_bp': 500, 'taxable_paise': 5714, 'cgst_paise': 0, 'sgst_paise': 0, 'igst_paise': 286},
        <String, dynamic>{'gst_rate_bp': 1200, 'taxable_paise': 27121, 'cgst_paise': 0, 'sgst_paise': 0, 'igst_paise': 3254},
      ],
    };

/// Answers every POST with one canned response.
class _FakeApi extends ApiClient {
  _FakeApi(this.status, this.body);
  final int status;
  final Map<String, dynamic>? body;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<({int status, Map<String, dynamic>? body})> postResult(String path, Map<String, dynamic> body,
      {String? token, Duration? timeout}) async {
    lastPath = path;
    lastBody = body;
    return (status: status, body: this.body);
  }

  @override
  Future<({int status, Map<String, dynamic>? body})> patchResult(String path, Map<String, dynamic> body,
      {String? token}) async {
    lastPath = 'PATCH $path';
    lastBody = body;
    return (status: status, body: this.body);
  }

  @override
  Future<({int status, Map<String, dynamic>? body})> getResult(String path,
          {Map<String, String>? query, String? token, Duration? timeout}) async =>
      (status: status, body: body);
}

void main() {
  test('a server bill parses with items, tax summary and seller', () {
    final Bill bill = Bill.fromJson(sampleBill());
    expect(bill.invoiceNo, 'MED/26-27/000042');
    expect(bill.billDate, DateTime(2026, 10, 5));
    expect(bill.paymentMode, PaymentMode.upi);
    expect(bill.isInterState, isTrue);
    expect(bill.placeOfSupplyLabel, '29 - Karnataka');
    expect(bill.seller.displayName, 'Sahay Medicals Pvt Ltd');
    expect(bill.items.map((BillItem i) => i.name), <String>['Dolo 650', 'Cough Syrup']);
    expect(bill.items[1].expiryDate, DateTime(2027, 1, 31));
    expect(bill.taxSummary.map((BillTaxRow t) => t.taxPaise), <int>[286, 3254]);
    expect(bill.unitCount, 5);
    expect(bill.isCancelled, isFalse);
  });

  test('POST /bills outcomes map to typed results', () async {
    BillResult r = await BillingApi(_FakeApi(201, <String, dynamic>{
      'bill': sampleBill(),
      'batches': <Map<String, dynamic>>[<String, dynamic>{'batch_id': 'b1', 'qty_units': 17}],
      'replayed': false,
    })).create('t', <String, Object?>{'id': 'x'});
    expect(r, isA<BillCreated>());
    expect((r as BillCreated).stock, <String, int>{'b1': 17});
    expect(r.replayed, isFalse);

    r = await BillingApi(_FakeApi(409, <String, dynamic>{
      'error': 'price_changed',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'batch_id': 'b1', 'name': 'Dolo 650', 'batch_no': 'B1',
          'sent_mrp_paise': 3000, 'mrp_paise': 3200, 'batch_version': 21, 'price_changed': true},
      ],
    })).create('t', <String, Object?>{});
    final StalePrice s = (r as BillPricesChanged).lines.single;
    expect(<Object>[s.sentMrpPaise, s.mrpPaise, s.version, s.priceChanged], <Object>[3000, 3200, 21, true]);

    r = await BillingApi(_FakeApi(422, <String, dynamic>{
      'error': 'insufficient_stock',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{'index': 1, 'batch_id': 'b1', 'name': 'Dolo 650', 'batch_no': 'B1',
          'requested_units': 6, 'available_units': 5},
      ],
    })).create('t', <String, Object?>{});
    expect((r as BillStockShort).lines.single.available, 5);

    r = await BillingApi(_FakeApi(422, <String, dynamic>{
      'error': 'batch_unavailable',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'batch_id': 'b9', 'name': null, 'batch_no': null, 'reason': 'expired'},
      ],
    })).create('t', <String, Object?>{});
    expect((r as BillBatchesUnavailable).lines.single.reason, 'expired');

    r = await BillingApi(_FakeApi(422, <String, dynamic>{
      'message': 'The customer name field is required when payment mode is credit.',
      'errors': <String, dynamic>{'customer_name': <String>['The customer name field is required when payment mode is credit.']},
    })).create('t', <String, Object?>{});
    expect((r as BillFailed).message, contains('customer name'));

    expect(await BillingApi(_FakeApi(0, null)).create('t', <String, Object?>{}), isA<BillOffline>());
  });

  test('editing a bill PATCHes it and maps the answers like create', () async {
    final _FakeApi fake = _FakeApi(200, <String, dynamic>{
      'bill': sampleBill()..['edited_at'] = '2026-10-06T10:00:00+05:30',
      'batches': <Map<String, dynamic>>[<String, dynamic>{'batch_id': 'b1', 'qty_units': 12}],
    });
    final BillResult r = await BillingApi(fake).update('t', 'bill-1', <String, Object?>{'payment_mode': 'cash', 'lines': <Object>[]});
    expect(fake.lastPath, 'PATCH /bills/bill-1');
    expect(fake.lastBody, <String, dynamic>{'payment_mode': 'cash', 'lines': <Object>[]});
    expect((r as BillCreated).stock, <String, int>{'b1': 12});
    expect(r.bill.editedAt, isNotNull);

    final BillResult short = await BillingApi(_FakeApi(422, <String, dynamic>{
      'error': 'insufficient_stock',
      'lines': <Map<String, dynamic>>[
        <String, dynamic>{'index': 0, 'batch_id': 'b1', 'requested_units': 30, 'available_units': 25},
      ],
    })).update('t', 'bill-1', <String, Object?>{});
    expect((short as BillStockShort).lines.single.available, 25);
    final BillResult refused = await BillingApi(_FakeApi(422, <String, dynamic>{
      'error': 'has_returns', 'message': 'This bill has a sale return (credit note), so it can’t be edited.',
    })).update('t', 'bill-1', <String, Object?>{});
    expect((refused as BillFailed).message, contains('can’t be edited'));
  });

  test('cancel sends the reason and returns the bill with the new stock', () async {
    final _FakeApi fake = _FakeApi(200, <String, dynamic>{
      'bill': sampleBill(status: 'cancelled'),
      'batches': <Map<String, dynamic>>[<String, dynamic>{'batch_id': 'b1', 'qty_units': 20}],
    });
    final ApiOutcome<(Bill, Map<String, int>)> r =
        await BillingApi(fake).cancel('t', 'bill-1', reason: ' Wrong medicine ', deviceId: 'pc');
    expect(fake.lastPath, '/bills/bill-1/cancel');
    expect(fake.lastBody, <String, dynamic>{'reason': 'Wrong medicine', 'device_id': 'pc'});
    expect(r.value!.$1.isCancelled, isTrue);
    expect(r.value!.$2, <String, int>{'b1': 20});
  });

  test('bill list page parses with the range summary', () {
    final BillPage page = BillPage.fromJson(<String, dynamic>{
      'data': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'invoice_no': 'INV/26-27/000003', 'bill_date': '2026-10-05',
          'created_at': '2026-10-05T10:00:00+05:30', 'status': 'cancelled', 'payment_mode': 'credit',
          'customer_name': null, 'customer_phone': null, 'total_paise': 9000, 'items_count': 1},
      ],
      'meta': <String, dynamic>{'current_page': 1, 'last_page': 2, 'per_page': 30, 'total': 31},
      'summary': <String, dynamic>{'count': 30, 'total_paise': 123400, 'cancelled_count': 1},
    });
    expect(page.hasMore, isTrue);
    expect(page.bills.single.isCancelled, isTrue);
    expect(page.bills.single.paymentMode, PaymentMode.credit);
    expect(<int>[page.finalCount, page.finalTotalPaise, page.cancelledCount], <int>[30, 123400, 1]);
  });

  test('WhatsApp link to the customer with a text summary', () {
    expect(InvoiceShare.whatsAppNumber('98765 43210'), '919876543210');
    expect(InvoiceShare.whatsAppNumber('+91 98765-43210'), '919876543210');
    expect(InvoiceShare.whatsAppNumber('098765 43210'), '919876543210');
    expect(InvoiceShare.whatsAppNumber('+1 415 555 0100'), '14155550100');
    expect(InvoiceShare.whatsAppNumber('12345'), isNull);
    expect(InvoiceShare.whatsAppNumber(null), isNull);

    final Bill bill = Bill.fromJson(sampleBill());
    final Uri uri = InvoiceShare.whatsAppUri(bill)!;
    expect(uri.host, 'wa.me');
    expect(uri.path, '/919876543210');
    final String text = uri.queryParameters['text']!;
    expect(text, contains('Invoice MED/26-27/000042'));
    expect(text, contains('Dolo 650 x 2 = ₹60.00'));
    expect(text, contains('*Total: ₹364.00* (UPI)'));
    expect(text, contains('Invoice MED/26-27/000042\nCustomer: City Clinic (98765 43210)\n'));
    expect(InvoiceShare.summary(Bill.fromJson(sampleBill(phone: null))), contains('Customer: City Clinic\n'));
    expect(InvoiceShare.summary(Bill.fromJson(sampleBill()..['customer_name'] = null)), isNot(contains('Customer')));
    expect(InvoiceShare.whatsAppUri(Bill.fromJson(sampleBill(phone: null))), isNull);
  });

  test('paid and balance: parsed, labelled, and on the WhatsApp text', () {
    final Bill paid = Bill.fromJson(sampleBill());
    expect(<Object>[paid.paidPaise, paid.balancePaise, paid.hasBalance, paid.paymentLabel, paid.paymentStatus],
        <Object>[36400, 0, false, 'UPI', 'Paid · UPI']);
    expect(paid.balanceLines, isEmpty);

    final Bill part = Bill.fromJson(sampleBill()
      ..['payment_mode'] = 'credit'
      ..['paid_paise'] = 10000
      ..['balance_paise'] = 26400
      ..['received_paise'] = 10000
      ..['received_mode'] = 'cash');
    expect(<Object?>[part.hasBalance, part.paymentLabel, part.paymentStatus, part.receivedPaise, part.receivedMode],
        <Object?>[true, 'Part paid', 'Part paid · ₹264.00 due', 10000, PaymentMode.cash]);
    expect(part.balanceLines, <(String, String)>[('Paid', '₹100.00'), ('Balance due', '₹264.00')]);
    final String text = InvoiceShare.summary(part);
    expect(text, contains('*Total: ₹364.00* (Part paid)\nPaid: ₹100.00\nBalance due: ₹264.00\n'));

    final Bill credit = Bill.fromJson(sampleBill()
      ..['payment_mode'] = 'credit'
      ..['paid_paise'] = 0
      ..['balance_paise'] = 36400);
    expect(<Object>[credit.paymentLabel, credit.paymentStatus], <Object>['Credit', 'Credit - to be paid']);
    final Bill settled = Bill.fromJson(sampleBill()
      ..['payment_mode'] = 'credit'
      ..['paid_paise'] = 36400
      ..['balance_paise'] = 0);
    expect(<Object>[settled.paymentLabel, settled.paymentStatus], <Object>['Paid', 'Paid']);

    final BillPage page = BillPage.fromJson(<String, dynamic>{
      'data': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'invoice_no': 'X', 'bill_date': '2026-10-05', 'status': 'final',
          'payment_mode': 'credit', 'total_paise': 9000, 'paid_paise': 1000, 'balance_paise': 8000},
      ],
      'summary': <String, dynamic>{'due_count': 3, 'due_paise': 42000},
    });
    expect(<Object>[page.bills.single.paidPaise, page.bills.single.balancePaise, page.bills.single.hasBalance],
        <Object>[1000, 8000, true]);
    expect(<int>[page.dueCount, page.duePaise], <int>[3, 42000]);
  });
}
