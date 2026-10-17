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
    this.retrying = false,
    this.canRetry = false,
    this.fileName,
    this.supplierName,
    this.invoiceNo,
    this.itemsCount,
    this.createdAt,
  });

  factory InvoiceScan.fromJson(Map<String, dynamic> j) {
    final Object? result = j['result'];
    return InvoiceScan(
      id: (j['id'] as num?)?.toInt() ?? 0,
      status: (j['status'] as String?) ?? 'failed',
      errorCode: j['error_code'] as String?,
      error: j['error'] as String?,
      result: result is Map<String, dynamic> ? result : null,
      retrying: j['retrying'] == true,
      canRetry: j['can_retry'] == true,
      fileName: j['file_name'] as String?,
      supplierName: j['supplier_name'] as String?,
      invoiceNo: j['invoice_no'] as String?,
      itemsCount: (j['items_count'] as num?)?.toInt(),
      createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal(),
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

  /// Waiting for the server's next try (AI service busy, or a bad reply).
  final bool retrying;

  /// Failed, but reading the same file again may work ([InvoiceScanService.retry]).
  final bool canRetry;

  // In the shop's list of bills ([InvoiceScanService.list]).
  final String? fileName;
  final String? supplierName;
  final String? invoiceNo;
  final int? itemsCount;
  final DateTime? createdAt;

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
/// (`POST /invoices/scan`, `GET /invoices/scan/{id}`, `GET /invoices/scans`,
/// `POST /invoices/scan/{id}/retry`, `POST /invoices/scan/{id}/close`).
/// Online only.
class InvoiceScanService {
  InvoiceScanService({http.Client? client, String? baseUrl, this.onUnauthorized})
    : _http = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiClient.baseUrl;

  final http.Client _http;
  final String _baseUrl;

  /// Called with the token when the server answers 401 (it no longer accepts
  /// this login), so the app signs out ([AuthService.sessionRejected]). Being
  /// offline or a server error only returns a message.
  void Function(String token)? onUnauthorized;

  static const String offlineMessage =
      "Can't reach the server. Reading invoices needs an internet connection.";

  /// Upload a photo or PDF ([filename] keeps its extension).
  Future<InvoiceScanResponse> upload({
    required String token,
    required List<int> bytes,
    required String filename,
  }) async {
    final http.Response res;
    try {
      final http.MultipartRequest req =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/invoices/scan'))
            ..headers.addAll(_headers(token))
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: filename),
            );
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 120)),
      );
    } catch (e) {
      debugPrint('[InvoiceScan] upload failed: $e');
      return const InvoiceScanResponse.error(offlineMessage, offline: true);
    }
    return _parse(res, token);
  }

  /// The scan's current status (and result once done).
  Future<InvoiceScanResponse> fetch({
    required String token,
    required int id,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .get(
            Uri.parse('$_baseUrl/invoices/scan/$id'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[InvoiceScan] poll failed: $e');
      return const InvoiceScanResponse.error(offlineMessage, offline: true);
    }
    return _parse(res, token);
  }

  /// Read a failed scan's file again, without uploading it again.
  Future<InvoiceScanResponse> retry({
    required String token,
    required int id,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('$_baseUrl/invoices/scan/$id/retry'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[InvoiceScan] retry failed: $e');
      return const InvoiceScanResponse.error(offlineMessage, offline: true);
    }
    return _parse(res, token);
  }

  /// The shop's bills still to deal with, newest first (no lines); null
  /// with [onError] called when the server can't be reached or refuses.
  Future<List<InvoiceScan>?> list({
    required String token,
    void Function(String message)? onError,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .get(Uri.parse('$_baseUrl/invoices/scans'), headers: _headers(token))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[InvoiceScan] list failed: $e');
      onError?.call(offlineMessage);
      return null;
    }
    if (res.statusCode == 401) onUnauthorized?.call(token);
    Map<String, dynamic>? body;
    try {
      final Object? decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    final Object? scans = body?['scans'];
    if (res.statusCode != 200 || scans is! List) {
      onError?.call(messageFor(res.statusCode, body));
      return null;
    }
    return <InvoiceScan>[
      for (final Object? s in scans)
        if (s is Map<String, dynamic>) InvoiceScan.fromJson(s),
    ];
  }

  /// Takes a bill off the shop's list (added to stock, or removed).
  Future<bool> close({required String token, required int id}) async {
    try {
      final http.Response res = await _http
          .post(
            Uri.parse('$_baseUrl/invoices/scan/$id/close'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401) onUnauthorized?.call(token);
      return res.statusCode == 204;
    } catch (e) {
      debugPrint('[InvoiceScan] close failed: $e');
      return false;
    }
  }

  static Map<String, String> _headers(String token) => <String, String>{
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };

  InvoiceScanResponse _parse(http.Response res, String token) {
    if (res.statusCode == 401) onUnauthorized?.call(token);
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
