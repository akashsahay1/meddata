import '../data/models/accounting.dart';
import 'api_client.dart';
import 'billing_api.dart';

/// A party with its unsettled credit bills / purchases (GET /parties/{id}).
class PartyDetail {
  const PartyDetail(this.party, this.openDocuments);
  final Party party;
  final List<OpenDocument> openDocuments;
}

/// What happened to a request that creates a document (purchase, return,
/// payment): the value, or the server's error code and message.
class DocResult<T> {
  const DocResult.ok(T this.value, {this.replayed = false})
      : status = 200,
        error = null,
        message = null,
        body = null;
  const DocResult.failed(this.status, this.error, this.message, this.body)
      : value = null,
        replayed = false;

  final T? value;
  final bool replayed;
  final int status;

  /// e.g. duplicate_invoice, return_exceeds_sold, over_allocated, plan_limit.
  final String? error;
  final String? message;
  final Map<String, dynamic>? body;

  bool get isOk => value != null;

  /// No answer: it may or may not have been saved, so retry with the same id.
  bool get isOffline => status == 0;
}

/// Accounting on the server (online-only, like billing): parties, ledgers,
/// payments, purchases, returns and the GSTR summaries.
class AccountingApi {
  AccountingApi([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;
  static const Duration _slow = Duration(seconds: 20);

  // ---- parties ----------------------------------------------------------------

  Future<ApiOutcome<ApiPage<Party>>> parties(String token,
      {String? type, String? query, int page = 1, int perPage = 50}) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.getResult('/parties', token: token, query: <String, String>{
      'type': ?type,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'page': '$page',
      'per_page': '$perPage',
    });
    if (r.status == 200 && r.body != null) {
      return ApiOutcome<ApiPage<Party>>.ok(ApiPage<Party>.fromJson(r.body!, Party.fromJson));
    }
    return ApiOutcome<ApiPage<Party>>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  Future<ApiOutcome<PartyDetail>> party(String token, String id) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.getResult('/parties/$id', token: token);
    final Object? p = r.body?['party'];
    if (r.status == 200 && p is Map) {
      return ApiOutcome<PartyDetail>.ok(PartyDetail(
        Party.fromJson(Map<String, dynamic>.from(p)),
        <OpenDocument>[
          for (final Object? d in (r.body!['open_documents'] as List<dynamic>?) ?? <dynamic>[])
            if (d is Map) OpenDocument.fromJson(Map<String, dynamic>.from(d)),
        ],
      ));
    }
    return ApiOutcome<PartyDetail>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  /// Create ([id] null) or change a party.
  Future<DocResult<Party>> saveParty(String token, Map<String, Object?> data, {String? id}) async {
    final ({int status, Map<String, dynamic>? body}) r = id == null
        ? await _api.postResult('/parties', Map<String, dynamic>.from(data), token: token, timeout: _slow)
        : await _api.patchResult('/parties/$id', Map<String, dynamic>.from(data), token: token);
    return _doc(r, 'party', Party.fromJson);
  }

  Future<DocResult<bool>> deleteParty(String token, String id) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.deleteResult('/parties/$id', token: token);
    if (r.status == 200) return const DocResult<bool>.ok(true);
    return _failed<bool>(r);
  }

  Future<ApiOutcome<Ledger>> ledger(String token, String partyId, {DateTime? from, DateTime? to}) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.getResult('/parties/$partyId/ledger', token: token, query: <String, String>{
      if (from != null) 'from': BillingApi.ymd(from),
      if (to != null) 'to': BillingApi.ymd(to),
    });
    if (r.status == 200 && r.body != null) return ApiOutcome<Ledger>.ok(Ledger.fromJson(r.body!));
    return ApiOutcome<Ledger>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  // ---- payments -----------------------------------------------------------------

  Future<DocResult<PartyPayment>> recordPayment(String token, Map<String, Object?> body) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.postResult('/payments', Map<String, dynamic>.from(body), token: token, timeout: _slow);
    return _doc(r, 'payment', PartyPayment.fromJson);
  }

  Future<DocResult<PartyPayment>> cancelPayment(String token, String id, {String? reason}) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.postResult(
        '/payments/$id/cancel', <String, dynamic>{if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
        token: token, timeout: _slow);
    return _doc(r, 'payment', PartyPayment.fromJson);
  }

  // ---- purchases ------------------------------------------------------------------

  Future<ApiOutcome<ApiPage<PurchaseSummary>>> purchases(String token,
      {DateTime? from, DateTime? to, String? partyId, String? query, int page = 1}) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.getResult('/purchases', token: token, query: <String, String>{
      if (from != null) 'from': BillingApi.ymd(from),
      if (to != null) 'to': BillingApi.ymd(to),
      'party_id': ?partyId,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'page': '$page',
    });
    if (r.status == 200 && r.body != null) {
      return ApiOutcome<ApiPage<PurchaseSummary>>.ok(ApiPage<PurchaseSummary>.fromJson(r.body!, PurchaseSummary.fromJson));
    }
    return ApiOutcome<ApiPage<PurchaseSummary>>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  Future<ApiOutcome<Purchase>> purchase(String token, String id) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.getResult('/purchases/$id', token: token);
    final Object? p = r.body?['purchase'];
    if (r.status == 200 && p is Map) return ApiOutcome<Purchase>.ok(Purchase.fromJson(Map<String, dynamic>.from(p)));
    return ApiOutcome<Purchase>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  Future<DocResult<Purchase>> createPurchase(String token, Map<String, Object?> body) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.postResult('/purchases', Map<String, dynamic>.from(body), token: token, timeout: _slow);
    return _doc(r, 'purchase', Purchase.fromJson);
  }

  Future<DocResult<Purchase>> cancelPurchase(String token, String id, {String? reason, String? deviceId}) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.postResult(
        '/purchases/$id/cancel',
        <String, dynamic>{
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          'device_id': ?deviceId,
        },
        token: token,
        timeout: _slow);
    return _doc(r, 'purchase', Purchase.fromJson);
  }

  // ---- returns -------------------------------------------------------------------

  Future<DocResult<ReturnNote>> createReturn(String token, Map<String, Object?> body, {required bool sale}) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.postResult(
        sale ? '/sale-returns' : '/purchase-returns', Map<String, dynamic>.from(body),
        token: token, timeout: _slow);
    return _doc(r, sale ? 'sale_return' : 'purchase_return', ReturnNote.fromJson);
  }

  Future<ApiOutcome<ReturnNote>> note(String token, String id, {required bool sale}) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.getResult(sale ? '/sale-returns/$id' : '/purchase-returns/$id', token: token);
    final Object? n = r.body?[sale ? 'sale_return' : 'purchase_return'];
    if (r.status == 200 && n is Map) return ApiOutcome<ReturnNote>.ok(ReturnNote.fromJson(Map<String, dynamic>.from(n)));
    return ApiOutcome<ReturnNote>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  // ---- GST -------------------------------------------------------------------------

  /// GET /gst/gstr1 or /gst/gstr3b for "2026-10" (the raw summary JSON).
  Future<ApiOutcome<Map<String, dynamic>>> gstReport(String token, String month, {required bool gstr1}) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.getResult(
        gstr1 ? '/gst/gstr1' : '/gst/gstr3b',
        token: token,
        query: <String, String>{'month': month},
        timeout: _slow);
    if (r.status == 200 && r.body != null) return ApiOutcome<Map<String, dynamic>>.ok(r.body!);
    return ApiOutcome<Map<String, dynamic>>.failed(r.status, BillingApi.errorMessage(r.status, r.body));
  }

  // ---------------------------------------------------------------------------------

  static DocResult<T> _doc<T>(({int status, Map<String, dynamic>? body}) r, String key,
      T Function(Map<String, dynamic>) parse) {
    final Object? v = r.body?[key];
    if ((r.status == 200 || r.status == 201) && v is Map) {
      return DocResult<T>.ok(parse(Map<String, dynamic>.from(v)), replayed: r.body?['replayed'] == true);
    }
    return _failed<T>(r);
  }

  static DocResult<T> _failed<T>(({int status, Map<String, dynamic>? body}) r) => DocResult<T>.failed(
        r.status,
        r.body?['error'] as String?,
        BillingApi.errorMessage(r.status, r.body),
        r.body,
      );
}
