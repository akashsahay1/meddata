import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/services/invoice_scan_service.dart';

void main() {
  const String base = 'https://api.test/api/v1';

  InvoiceScanService service(
    Future<http.Response> Function(http.Request r) handler,
  ) => InvoiceScanService(client: MockClient(handler), baseUrl: base);

  http.Response json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  test('uploads the file as multipart with the bearer token', () async {
    late http.Request sent;
    final InvoiceScanResponse r =
        await service((http.Request req) async {
          sent = req;
          return json(<String, dynamic>{
            'scan': <String, dynamic>{
              'id': 7,
              'status': 'queued',
              'result': null,
            },
          }, 202);
        }).upload(
          token: 'tok',
          bytes: utf8.encode('jpeg-bytes'),
          filename: 'bill.jpg',
        );

    expect(sent.method, 'POST');
    expect(sent.url.toString(), '$base/invoices/scan');
    expect(sent.headers['Authorization'], 'Bearer tok');
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    expect(sent.body, contains('name="file"; filename="bill.jpg"'));
    expect(sent.body, contains('jpeg-bytes'));
    expect(r.scan!.id, 7);
    expect(r.scan!.isPending, isTrue);
    expect(r.offline, isFalse);
  });

  test('polls a finished scan with its result', () async {
    final InvoiceScanResponse r = await service((http.Request req) async {
      expect(req.url.toString(), '$base/invoices/scan/7');
      return json(<String, dynamic>{
        'scan': <String, dynamic>{
          'id': 7,
          'status': 'done',
          'error': null,
          'result': <String, dynamic>{'invoice_no': 'A1', 'items': <Object>[]},
        },
      }, 200);
    }).fetch(token: 'tok', id: 7);

    expect(r.scan!.isDone, isTrue);
    expect(r.scan!.result!['invoice_no'], 'A1');
  });

  test('a failed scan carries the reason to show', () async {
    final InvoiceScanResponse r = await service(
      (_) async => json(<String, dynamic>{
        'scan': <String, dynamic>{
          'id': 7,
          'status': 'failed',
          'error_code': 'not_configured',
          'error': 'AI invoice reading is not set up on the server yet.',
        },
      }, 200),
    ).fetch(token: 'tok', id: 7);

    expect(r.scan!.isFailed, isTrue);
    expect(r.scan!.errorCode, 'not_configured');
    expect(r.scan!.error, contains('not set up'));
  });

  test('errors become messages, preferring the server wording', () async {
    Future<InvoiceScanResponse> reply(Object body, int status) => service(
      (_) async => json(body, status),
    ).upload(token: 't', bytes: <int>[1], filename: 'a.jpg');

    expect(
      (await reply(<String, dynamic>{
        'message': 'The given data was invalid.',
        'errors': <String, dynamic>{
          'file': <String>['The photo is too large (7 MB at most).'],
        },
      }, 422)).message,
      'The photo is too large (7 MB at most).',
    );
    expect(
      (await reply(<String, dynamic>{
        'error': 'premium_required',
        'message': 'Reading invoices needs an active trial or subscription.',
      }, 403)).message,
      'Reading invoices needs an active trial or subscription.',
    );
    expect(
      (await reply(<String, dynamic>{
        'message': 'Too many invoices scanned.',
      }, 429)).message,
      'Too many invoices scanned.',
    );
    expect(
      (await reply(<String, dynamic>{}, 401)).message,
      contains('log in again'),
    );
    expect(
      (await reply('<html>oops</html>', 500)).message,
      contains('server had a problem'),
    );
  });

  test('no connection is reported as offline', () async {
    final InvoiceScanResponse r = await service((_) async {
      throw http.ClientException('Failed host lookup');
    }).upload(token: 't', bytes: <int>[1], filename: 'a.jpg');

    expect(r.scan, isNull);
    expect(r.offline, isTrue);
    expect(r.message, InvoiceScanService.offlineMessage);
  });
}
