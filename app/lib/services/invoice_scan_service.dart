import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

/// A purchase invoice the server is reading (or has read) with AI.
class InvoiceScan {
  const InvoiceScan({
    required this.id,
    required this.status,
    this.errorCode,
    this.error,
    this.result,
  });

  factory InvoiceScan.fromJson(Map<String, dynamic> j) {
    final Object? result = j['result'];
    return InvoiceScan(
      id: (j['id'] as num?)?.toInt() ?? 0,
      status: (j['status'] as String?) ?? 'failed',
      errorCode: j['error_code'] as String?,
      error: j['error'] as String?,
      result: result is Map<String, dynamic> ? result : null,
    );
  }

  final int id;

  /// queued | processing | done | failed
  final String status;
  final String? errorCode;

  /// Why it failed, ready to show.
  final String? error;

  /// The extracted invoice once done (see InvoiceDraftMapper).
  final Map<String, dynamic>? result;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isPending => !isDone && !isFailed;
}

/// The outcome of one call: a scan, or a message to show the user.
class InvoiceScanResponse {
  const InvoiceScanResponse.ok(InvoiceScan this.scan)
    : message = null,
      offline = false;
  const InvoiceScanResponse.error(String this.message, {this.offline = false})
    : scan = null;

  final InvoiceScan? scan;
  final String? message;

  /// The server could not be reached at all.
  final bool offline;
}

/// Uploads purchase invoices for AI reading and polls the result
/// (`POST /invoices/scan`, `GET /invoices/scan/{id}`). Online only.
class InvoiceScanService {
  InvoiceScanService({http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiClient.baseUrl;

  final http.Client _http;
  final String _baseUrl;

  static const String offlineMessage =
      "Can't reach the server. Reading invoices needs an internet connection.";

  /// Upload a photo or PDF ([filename] keeps its extension).
  Future<InvoiceScanResponse> upload({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final http.MultipartRequest req =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/invoices/scan'))
            ..headers.addAll(_headers(token))
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename),
            );
      final http.Response res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 120)),
      );
      return _parse(res);
    } catch (e) {
      debugPrint('[InvoiceScan] upload failed: $e');
      return const InvoiceScanResponse.error(offlineMessage, offline: true);
    }
  }

  /// The scan's current status (and result once done).
  Future<InvoiceScanResponse> fetch({
    required String token,
    required int id,
  }) async {
    try {
      final http.Response res = await _http
          .get(
            Uri.parse('$_baseUrl/invoices/scan/$id'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 20));
      return _parse(res);
    } catch (e) {
      debugPrint('[InvoiceScan] poll failed: $e');
      return const InvoiceScanResponse.error(offlineMessage, offline: true);
    }
  }

  static Map<String, String> _headers(String token) => <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static InvoiceScanResponse _parse(http.Response res) {
    Map<String, dynamic>? body;
    try {
      final Object? decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    final Object? scan = body?['scan'];
    if (res.statusCode >= 200 &&
        res.statusCode < 300 &&
        scan is Map<String, dynamic>) {
      return InvoiceScanResponse.ok(InvoiceScan.fromJson(scan));
    }
    return InvoiceScanResponse.error(messageFor(res.statusCode, body));
  }

  /// A message for a failed call, preferring the server's own wording.
  static String messageFor(int status, Map<String, dynamic>? body) {
    final Object? errors = body?['errors'];
    if (status == 422 && errors is Map) {
      for (final Object? list in errors.values) {
        if (list is List && list.isNotEmpty && list.first is String) {
          return list.first as String;
        }
      }
    }
    final Object? message = body?['message'];
    final String? serverMessage = message is String && message.isNotEmpty
        ? message
        : null;
    switch (status) {
      case 401:
        return 'Your session has expired. Please log in again.';
      case 403:
        return serverMessage ??
            'Reading invoices needs an active trial or subscription.';
      case 404:
        return 'This scan was not found. Please scan the invoice again.';
      case 413:
        return 'The file is too large to upload.';
      case 429:
        return serverMessage ??
            'Too many invoices scanned. Please try again later.';
    }
    if (status >= 500) return 'The server had a problem. Please try again.';
    return serverMessage ?? 'Something went wrong (error $status).';
  }
}
