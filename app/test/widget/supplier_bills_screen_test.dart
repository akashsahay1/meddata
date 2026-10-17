// A shop hands over a pile of supplier bills at once: they upload together,
// the server reads them in turn, and the list shows each one's state until
// it is checked and added (or removed).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medikabiz/presentation/screens/invoice_scan_screen.dart';
import 'package:medikabiz/presentation/screens/supplier_bills_screen.dart';
import 'package:medikabiz/presentation/widgets/ui_kit.dart';
import 'package:medikabiz/services/invoice_scan_service.dart';

import '../support/test_app.dart';

/// The server's bills, and every call the screen made.
class _Server {
  final List<String> calls = <String>[];
  final List<String> uploaded = <String>[];
  List<Map<String, Object?>> bills = <Map<String, Object?>>[];

  late final InvoiceScanService service = InvoiceScanService(
    baseUrl: 'http://api.test',
    client: MockClient((http.Request r) async {
      final String path = r.url.path;
      calls.add('${r.method} $path');
      http.Response json(Object body, [int status = 200]) =>
          http.Response(jsonEncode(body), status);
      if (path == '/invoices/scans') {
        return json(<String, Object?>{'scans': bills});
      }
      if (r.method == 'POST' && path == '/invoices/scan') {
        uploaded.add(
          RegExp(r'filename="([^"]+)"').firstMatch(r.body)?.group(1) ?? '?',
        );
        return json(<String, Object?>{
          'scan': <String, Object?>{
            'id': 100 + uploaded.length,
            'status': 'queued',
          },
        }, 202);
      }
      if (path.endsWith('/close')) return http.Response('', 204);
      if (path.endsWith('/retry')) {
        return json(<String, Object?>{
          'scan': <String, Object?>{'id': 2, 'status': 'queued'},
        }, 202);
      }
      if (path == '/invoices/scan/1') {
        return json(<String, Object?>{
          'scan': <String, Object?>{
            'id': 1,
            'status': 'done',
            'result': <String, Object?>{
              'supplier_name': 'Om Sai Medical Agencies',
              'invoice_no': 'OSMA-26-11873',
              'invoice_date': '2026-10-09',
              'items': <Object>[
                <String, Object?>{
                  'product_name': 'Combiflam Tab',
                  'batch_no': 'DB74089',
                  'expiry_date': '2027-07-31',
                  'quantity': 12,
                  'mrp': 44,
                  'purchase_rate': 28.8,
                },
              ],
            },
          },
        });
      }
      return json(<String, Object?>{'message': 'Not found'}, 404);
    }),
  );
}

Map<String, Object?> _bill(
  int id,
  String status, {
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  'id': id,
  'status': status,
  'created_at': '2026-10-17T09:30:00+05:30',
  ...extra,
};

void main() {
  setUpAll(loadAppFont);

  Future<(TestApp, _Server)> open(
    WidgetTester tester,
    _Server server, {
    Future<List<XFile>> Function()? pickFiles,
  }) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final TestApp app = await TestApp.create(signedIn: true);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      app.wrap(
        SupplierBillsScreen(service: server.service, pickFiles: pickFiles),
      ),
    );
    await tester.pumpAndSettle();
    return (app, server);
  }

  testWidgets('each bill shows where it is: waiting, reading, trying again, '
      'ready to check, or what went wrong', (WidgetTester tester) async {
    final _Server server = _Server()
      ..bills = <Map<String, Object?>>[
        _bill(5, 'queued', extra: <String, Object?>{'file_name': 'gupta.jpg'}),
        _bill(
          4,
          'processing',
          extra: <String, Object?>{'file_name': 'arogya.pdf'},
        ),
        _bill(
          3,
          'queued',
          extra: <String, Object?>{'file_name': 'balaji.pdf', 'retrying': true},
        ),
        _bill(
          2,
          'failed',
          extra: <String, Object?>{
            'file_name': 'photo_0412.jpg',
            'can_retry': true,
            'error':
                'The AI service is busy right now. Please try again in a few minutes.',
          },
        ),
        _bill(
          1,
          'done',
          extra: <String, Object?>{
            'file_name': 'om_sai.pdf',
            'supplier_name': 'Om Sai Medical Agencies',
            'invoice_no': 'OSMA-26-11873',
            'items_count': 10,
          },
        ),
      ];
    await open(tester, server);

    expect(find.textContaining('Waiting to be read'), findsOneWidget);
    expect(find.textContaining('Reading…'), findsOneWidget);
    expect(
      find.textContaining('AI service busy, trying again by itself'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The AI service is busy right now'),
      findsOneWidget,
    );
    expect(find.text('Om Sai Medical Agencies'), findsOneWidget);
    expect(
      find.textContaining('Ready to check · 10 items · OSMA-26-11873'),
      findsOneWidget,
    );

    // Something is still being read, so the list refreshes by itself.
    server.bills = <Map<String, Object?>>[
      _bill(
        5,
        'done',
        extra: <String, Object?>{
          'supplier_name': 'Gupta Medicos',
          'items_count': 6,
        },
      ),
    ];
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Gupta Medicos'), findsOneWidget);
    expect(find.textContaining('Waiting to be read'), findsNothing);
  });

  testWidgets('a failed bill is tried again or removed; a ready one opens '
      'for checking', (WidgetTester tester) async {
    final _Server server = _Server()
      ..bills = <Map<String, Object?>>[
        _bill(
          2,
          'failed',
          extra: <String, Object?>{
            'file_name': 'photo_0412.jpg',
            'can_retry': true,
            'error': 'The AI service is busy right now.',
          },
        ),
        _bill(
          1,
          'done',
          extra: <String, Object?>{
            'supplier_name': 'Om Sai Medical Agencies',
            'items_count': 1,
          },
        ),
      ];
    await open(tester, server);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SecondaryButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(
      server.calls,
      containsAllInOrder(<String>[
        'POST /invoices/scan/2/retry',
        'POST /invoices/scan/2/close',
      ]),
    );

    await tester.tap(find.text('Om Sai Medical Agencies'));
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceScanScreen), findsOneWidget);
    expect(find.text('Combiflam Tab'), findsWidgets);
  });

  testWidgets('many bills are uploaded at once; one that is not a photo or '
      'PDF is named with the reason', (WidgetTester tester) async {
    final _Server server = _Server();
    XFile file(String name) => XFile.fromData(
      Uint8List.fromList(utf8.encode('%PDF-1.4 $name')),
      name: name,
      path: name,
    );
    await open(
      tester,
      server,
      pickFiles: () async => <XFile>[
        file('om_sai.pdf'),
        file('stock.xlsx'),
        file('arogya.pdf'),
      ],
    );
    expect(find.textContaining('No bills waiting'), findsOneWidget);

    server.bills = <Map<String, Object?>>[
      _bill(102, 'queued'),
      _bill(101, 'queued'),
    ];
    await tester.tap(
      find.widgetWithText(PrimaryButton, 'Add bills (photos or PDFs)'),
    );
    await tester.pumpAndSettle();

    expect(server.uploaded, <String>['om_sai.pdf', 'arogya.pdf']);
    expect(
      find.text('stock.xlsx: Choose a JPG, PNG or WebP photo, or a PDF.'),
      findsOneWidget,
    );
    expect(find.textContaining('Waiting to be read'), findsNWidgets(2));
  });
}
