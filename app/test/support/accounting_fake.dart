// A fake accounting server (parties, ledgers, payments, purchases, returns,
// GST summaries) for widget tests, plus a signed-in app shell to show the
// accounts screens in.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/data/db/database_helper.dart';
import 'package:med_stock/data/repositories/medicine_repository.dart';
import 'package:med_stock/services/accounting_api.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/state/medicine_provider.dart';
import 'package:med_stock/sync/sync_engine.dart';
import 'package:med_stock/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart' show memoryDatabase;

/// The token in memory (platform secure storage never answers under
/// `flutter test`).
class MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> delete() async => value = null;
}

Map<String, Object?> partyJson(String id, String name,
        {String type = 'customer', int balance = 0, String? phone, String? gstin, String? state}) =>
    <String, Object?>{
      'id': id,
      'type': type,
      'name': name,
      'phone': phone,
      'gstin': gstin,
      'state_code': state ?? (gstin?.substring(0, 2)),
      'opening_balance_paise': 0,
      'balance_paise': balance,
    };

/// Answers the accounting endpoints from in-memory data and records every
/// request ([requests]: "METHOD /path" plus the JSON body, if any).
class FakeAccountsServer {
  FakeAccountsServer() {
    parties.addAll(<Map<String, Object?>>[
      partyJson('p-ramesh', 'Ramesh Kumar', balance: 120000, phone: '9876543210'),
      partyJson('p-ppd', 'Pune Pharma Distributors', type: 'supplier', balance: -560000, gstin: '27AABCU9603R1ZN'),
      partyJson('p-asha', 'Asha Clinic', type: 'both'),
    ]);
  }

  final List<Map<String, Object?>> parties = <Map<String, Object?>>[];
  final List<(String, Map<String, dynamic>?)> requests = <(String, Map<String, dynamic>?)>[];

  /// Scripted answer to the next POST /purchases (default: 201 created).
  (int, Map<String, Object?>)? purchaseAnswer;

  /// What POST /bills answers with (a created bill).
  Map<String, Object?> billAnswer = const <String, Object?>{
    'id': 'b-9',
    'invoice_no': 'MED/26-27/000009',
    'bill_date': '2026-10-05',
    'status': 'final',
    'payment_mode': 'credit',
    'party_id': 'p-ramesh',
    'customer_name': 'Ramesh Kumar',
    'seller': <String, Object?>{'name': 'Sahay Medicals'},
    'total_paise': 3000,
    'items': <Object?>[],
  };
  bool offline = false;

  late final ApiClient client = ApiClient(MockClient(_handle));
  late final AccountingApi api = AccountingApi(client);

  List<String> get paths => requests.map(((String, Map<String, dynamic>?) r) => r.$1).toList();
  Map<String, dynamic>? bodyOf(String request) =>
      requests.lastWhere(((String, Map<String, dynamic>?) r) => r.$1 == request).$2;

  static const Map<String, Object?> ledger = <String, Object?>{
    'from': null,
    'to': null,
    'opening_paise': 10000,
    'closing_paise': 120000,
    'debit_paise': 160000,
    'credit_paise': 50000,
    'seller': <String, Object?>{'name': 'Sahay Medicals', 'gstin': '27AAPFU0939F1ZV', 'state_code': '27'},
    'entries': <Object?>[
      <String, Object?>{
        'type': 'sale', 'id': 'b-1', 'number': 'MED/26-27/000001', 'date': '2026-10-01',
        'description': 'Credit sale', 'debit_paise': 160000, 'credit_paise': 0, 'balance_paise': 170000,
      },
      <String, Object?>{
        'type': 'payment_in', 'id': 'pay-1', 'number': 'UPI-77', 'date': '2026-10-03',
        'description': 'Payment received · UPI UPI-77', 'debit_paise': 0, 'credit_paise': 50000, 'balance_paise': 120000,
      },
    ],
  };

  static Map<String, Object?> purchase({bool cancelled = false}) => <String, Object?>{
        'id': 'pur-1',
        'party_id': 'p-ppd',
        'supplier_name': 'Pune Pharma Distributors',
        'supplier_gstin': '27AABCU9603R1ZN',
        'supplier_invoice_no': 'PPD/42',
        'invoice_date': '2026-10-03',
        'is_inter_state': false,
        'subtotal_paise': 50000,
        'discount_paise': 5000,
        'taxable_paise': 45000,
        'cgst_paise': 2700,
        'sgst_paise': 2700,
        'igst_paise': 0,
        'round_off_paise': 0,
        'total_paise': 50400,
        'outstanding_paise': cancelled ? 0 : 50400,
        'status': cancelled ? 'cancelled' : 'final',
        'items': <Object?>[
          <String, Object?>{
            'id': 11, 'line_no': 1, 'product_id': 'prod-1', 'batch_id': 'bat-1', 'name': 'Azithral 500',
            'hsn': '3004', 'batch_no': 'AZ9', 'expiry_date': '2028-03-31', 'qty': 10, 'free_qty': 2,
            'units_per_pack': 1, 'stock_units': 12, 'rate_paise': 5000, 'mrp_paise': 11200, 'discount_bp': 1000,
            'gst_rate_bp': 1200, 'taxable_paise': 45000, 'cgst_paise': 2700, 'sgst_paise': 2700, 'igst_paise': 0,
            'total_paise': 50400, 'returned_qty': 0,
          },
        ],
      };

  static Map<String, Object?> note({required bool credit, int qty = 2}) => <String, Object?>{
        'id': credit ? 'cn-1' : 'dn-1',
        'kind': credit ? 'credit_note' : 'debit_note',
        'note_no': credit ? 'CN/26-27/000001' : 'DN/26-27/000001',
        'return_date': '2026-10-05',
        'bill_invoice_no': 'MED/26-27/000001',
        'supplier_invoice_no': 'PPD/42',
        'party_name': credit ? 'Ramesh Kumar' : 'Pune Pharma Distributors',
        'refund_mode': credit ? 'credit' : null,
        'is_inter_state': false,
        'place_of_supply': '27',
        'seller': <String, Object?>{'name': 'Sahay Medicals', 'gstin': '27AAPFU0939F1ZV'},
        'taxable_paise': 8929 * qty,
        'cgst_paise': 536 * qty,
        'sgst_paise': 536 * qty,
        'igst_paise': 0,
        'round_off_paise': 0,
        'total_paise': 10001 * qty,
        'items': <Object?>[
          <String, Object?>{
            'name': credit ? 'Dolo 650' : 'Azithral 500', 'batch_no': 'B1', 'qty': qty, 'rate_paise': 11200,
            'discount_bp': 0, 'gst_rate_bp': 1200, 'taxable_paise': 8929 * qty, 'cgst_paise': 536 * qty,
            'sgst_paise': 536 * qty, 'igst_paise': 0, 'total_paise': 10001 * qty,
          },
        ],
        'tax_summary': <Object?>[
          <String, Object?>{'gst_rate_bp': 1200, 'taxable_paise': 8929 * qty, 'cgst_paise': 536 * qty, 'sgst_paise': 536 * qty, 'igst_paise': 0},
        ],
      };

  static const Map<String, Object?> gstr1 = <String, Object?>{
    'return': 'GSTR-1',
    'month': '2026-10',
    'gstin': '27AAPFU0939F1ZV',
    'registered': true,
    'disclaimer': 'Prepared by Meddata from your bills and purchases for review by your CA.',
    'b2b': <Object?>[
      <String, Object?>{
        'gstin': '29AABCU9603R1ZJ', 'name': 'Lakshmi Clinic', 'invoice_count': 1, 'invoice_value_paise': 44800,
        'taxable_paise': 40000, 'igst_paise': 4800, 'cgst_paise': 0, 'sgst_paise': 0,
        'invoices': <Object?>[
          <String, Object?>{
            'invoice_no': 'MED/26-27/000002', 'invoice_date': '2026-10-02', 'invoice_value_paise': 44800,
            'place_of_supply': '29', 'reverse_charge': 'N',
            'rates': <Object?>[
              <String, Object?>{'gst_rate_bp': 1200, 'taxable_paise': 40000, 'igst_paise': 4800, 'cgst_paise': 0, 'sgst_paise': 0},
            ],
          },
        ],
      },
    ],
    'b2cl': <Object?>[],
    'b2cs': <Object?>[
      <String, Object?>{
        'place_of_supply': '27', 'gst_rate_bp': 500, 'supply_type': 'INTRA', 'type': 'OE',
        'taxable_paise': 100000, 'igst_paise': 0, 'cgst_paise': 2500, 'sgst_paise': 2500,
      },
    ],
    'cdnr': <Object?>[],
    'cdnur': <Object?>[],
    'nil_rated': <Object?>[],
    'hsn': <String, Object?>{
      'b2b': <Object?>[
        <String, Object?>{'hsn': '3004', 'unit': 'Strips', 'gst_rate_bp': 1200, 'qty': 4, 'total_value_paise': 44800,
          'taxable_paise': 40000, 'igst_paise': 4800, 'cgst_paise': 0, 'sgst_paise': 0},
      ],
      'b2c': <Object?>[],
    },
    'documents': <Object?>[
      <String, Object?>{'nature': 'Invoices for outward supply', 'from': 'MED/26-27/000001', 'to': 'MED/26-27/000003',
        'total': 3, 'cancelled': 1, 'net_issued': 2},
    ],
    'summary': <String, Object?>{
      'bills': <String, Object?>{'count': 2},
      'credit_notes': <String, Object?>{'count': 0},
      'net': <String, Object?>{'taxable_paise': 140000, 'igst_paise': 4800, 'cgst_paise': 2500, 'sgst_paise': 2500},
    },
  };

  static const Map<String, Object?> gstr3b = <String, Object?>{
    'return': 'GSTR-3B',
    'month': '2026-10',
    'gstin': '27AAPFU0939F1ZV',
    'registered': true,
    'disclaimer': 'Prepared by Meddata from your bills and purchases for review by your CA.',
    'outward_taxable': <String, Object?>{'taxable_paise': 140000, 'igst_paise': 4800, 'cgst_paise': 2500, 'sgst_paise': 2500},
    'outward_nil_rated': <String, Object?>{'taxable_paise': 0},
    'inter_state_unregistered': <Object?>[],
    'itc': <String, Object?>{
      'available': <String, Object?>{'taxable_paise': 45000, 'igst_paise': 0, 'cgst_paise': 2700, 'sgst_paise': 2700},
      'reversed': <String, Object?>{'taxable_paise': 0, 'igst_paise': 0, 'cgst_paise': 0, 'sgst_paise': 0},
      'net': <String, Object?>{'igst_paise': 0, 'cgst_paise': 2700, 'sgst_paise': 2700},
    },
    'payment': <String, Object?>{
      'tax_payable': <String, Object?>{'igst_paise': 4800, 'cgst_paise': 2500, 'sgst_paise': 2500},
      'itc_used': <String, Object?>{'igst_paise': 0, 'cgst_paise': 2700, 'sgst_paise': 2500},
      'cash_payable': <String, Object?>{'igst_paise': 4600, 'cgst_paise': 0, 'sgst_paise': 0, 'total_paise': 4600},
      'itc_carried_forward': <String, Object?>{'igst_paise': 0, 'cgst_paise': 0, 'sgst_paise': 200, 'total_paise': 200},
    },
  };

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: <String, String>{'content-type': 'application/json'});

  Future<http.Response> _handle(http.Request req) async {
    final String path = req.url.path.replaceFirst(RegExp(r'^.*/api/v1'), '');
    Map<String, dynamic>? body;
    if (req.body.isNotEmpty) body = jsonDecode(req.body) as Map<String, dynamic>;
    requests.add(('${req.method} $path', body ?? (req.url.queryParameters.isEmpty ? null : req.url.queryParameters)));
    if (offline) throw http.ClientException('offline');

    final List<String> seg = path.split('/').where((String s) => s.isNotEmpty).toList();
    switch ((req.method, seg)) {
      case ('GET', <String>['parties']):
        final String? type = req.url.queryParameters['type'];
        final String q = (req.url.queryParameters['q'] ?? '').toLowerCase();
        final List<Map<String, Object?>> found = parties.where((Map<String, Object?> p) {
          final bool typeOk = type == null || p['type'] == type || p['type'] == 'both';
          final String hay = '${p['name']} ${p['phone'] ?? ''} ${p['gstin'] ?? ''}'.toLowerCase();
          return typeOk && (q.isEmpty || hay.contains(q));
        }).toList();
        return _json(<String, Object?>{
          'data': found,
          'meta': <String, Object?>{'current_page': 1, 'last_page': 1},
        });
      case ('POST', <String>['parties']):
        final Map<String, Object?> p = partyJson(body!['id'] as String, body['name'] as String,
            type: body['type'] as String, phone: body['phone'] as String?, gstin: body['gstin'] as String?,
            balance: (body['opening_balance_paise'] as int?) ?? 0);
        parties.add(p);
        return _json(<String, Object?>{'party': p}, 201);
      case ('GET', <String>['parties', final String id]):
        return _json(<String, Object?>{
          'party': parties.firstWhere((Map<String, Object?> p) => p['id'] == id),
          'open_documents': <Object?>[
            if (id == 'p-ramesh')
              <String, Object?>{'type': 'bill', 'id': 'b-1', 'number': 'MED/26-27/000001', 'date': '2026-10-01',
                'total_paise': 160000, 'outstanding_paise': 110000},
          ],
        });
      case ('GET', <String>['parties', final String id, 'ledger']):
        return _json(<String, Object?>{...ledger, 'party': parties.firstWhere((Map<String, Object?> p) => p['id'] == id)});
      case ('POST', <String>['payments']):
        return _json(<String, Object?>{
          'payment': <String, Object?>{...body!, 'status': 'active'},
          'balance_paise': 0,
        }, 201);
      case ('POST', <String>['payments', final String id, 'cancel']):
        return _json(<String, Object?>{
          'payment': <String, Object?>{'id': id, 'party_id': 'p-ramesh', 'direction': 'in', 'amount_paise': 50000,
            'mode': 'upi', 'payment_date': '2026-10-03', 'status': 'cancelled'},
          'balance_paise': 170000,
        });
      case ('GET', <String>['purchases']):
        return _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'pur-1', 'supplier_name': 'Pune Pharma Distributors', 'supplier_invoice_no': 'PPD/42',
              'invoice_date': '2026-10-03', 'status': 'final', 'total_paise': 50400, 'items_count': 1},
          ],
          'meta': <String, Object?>{'current_page': 1, 'last_page': 1},
          'summary': <String, Object?>{'count': 1, 'total_paise': 50400},
        });
      case ('GET', <String>['purchases', _]):
        return _json(<String, Object?>{'purchase': purchase()});
      case ('POST', <String>['purchases']):
        final (int, Map<String, Object?>) a =
            purchaseAnswer ?? (201, <String, Object?>{'purchase': purchase(), 'batches': <Object?>[], 'replayed': false});
        return _json(a.$2, a.$1);
      case ('POST', <String>['purchases', _, 'cancel']):
        return _json(<String, Object?>{'purchase': purchase(cancelled: true), 'batches': <Object?>[]});
      case ('POST', <String>['sale-returns']):
        final int qty = ((body!['lines'] as List<dynamic>).first as Map<String, dynamic>)['qty_units'] as int;
        return _json(<String, Object?>{'sale_return': note(credit: true, qty: qty), 'batches': <Object?>[]}, 201);
      case ('POST', <String>['purchase-returns']):
        final int qty = ((body!['lines'] as List<dynamic>).first as Map<String, dynamic>)['qty'] as int;
        return _json(<String, Object?>{'purchase_return': note(credit: false, qty: qty), 'batches': <Object?>[]}, 201);
      case ('GET', <String>['sale-returns', _]):
        return _json(<String, Object?>{'sale_return': note(credit: true)});
      case ('GET', <String>['purchase-returns', _]):
        return _json(<String, Object?>{'purchase_return': note(credit: false)});
      case ('GET', <String>['shops', 'current']):
        return _json(<String, Object?>{
          'shop': <String, Object?>{'name': 'Sahay Medicals', 'gstin': '27AAPFU0939F1ZV', 'state_code': '27',
            'address': '12 Station Road', 'default_gst_rate_bp': 500},
        });
      case ('POST', <String>['bills']):
        return _json(<String, Object?>{'bill': billAnswer, 'batches': <Object?>[], 'replayed': false}, 201);
      case ('GET', <String>['gst', 'gstr1']):
        return _json(gstr1);
      case ('GET', <String>['gst', 'gstr3b']):
        return _json(gstr3b);
    }
    return _json(<String, Object?>{'message': 'Not found.'}, 404);
  }
}

/// A signed-in shop (token "tok") over an in-memory inventory, for showing
/// the accounts screens.
class AccountsApp {
  AccountsApp._(this.db, this.auth, this.medicines, this.sync, this.server);

  final DatabaseHelper db;
  final AuthService auth;
  final MedicineProvider medicines;
  final SyncEngine sync;
  final FakeAccountsServer server;
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  static Future<AccountsApp> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok', 'auth_email': 'a@b.c'});
    final AuthService auth = AuthService(SettingsService(), 'phone-1', null, MemoryTokenStore());
    await auth.init();
    final DatabaseHelper db = memoryDatabase();
    final MedicineProvider meds = MedicineProvider(MedicineRepository(db))..isPremium = true;
    await meds.load();
    final SyncEngine sync = SyncEngine(tokenProvider: () => null, userKeyProvider: () => null, db: db);
    return AccountsApp._(db, auth, meds, sync, FakeAccountsServer());
  }

  Widget wrap(Widget home) => MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<MedicineProvider>.value(value: medicines),
          ChangeNotifierProvider<SyncEngine>.value(value: sync),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: home,
        ),
      );

  /// An empty app with [screen] opened on top (so it can pop itself).
  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(wrap(const Scaffold(body: Text('home'))));
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    sync.dispose();
    await db.close();
  }
}
