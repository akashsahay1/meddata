import '../data/models/bill.dart';
import 'api_client.dart';

/// A price the server refused: the batch's MRP (or the batch itself)
/// changed after this device loaded it. "₹X is now ₹Y".
class StalePrice {
  const StalePrice({
    required this.index,
    required this.batchId,
    required this.name,
    required this.batchNo,
    required this.sentMrpPaise,
    required this.mrpPaise,
    required this.version,
    required this.priceChanged,
  });

  factory StalePrice.fromJson(Map<String, dynamic> j) => StalePrice(
        index: (j['index'] as num?)?.toInt() ?? 0,
        batchId: '${j['batch_id']}',
        name: (j['name'] as String?) ?? '',
        batchNo: (j['batch_no'] as String?) ?? '',
        sentMrpPaise: (j['sent_mrp_paise'] as num?)?.toInt() ?? 0,
        mrpPaise: (j['mrp_paise'] as num?)?.toInt() ?? 0,
        version: (j['batch_version'] as num?)?.toInt() ?? 0,
        priceChanged: j['price_changed'] == true,
      );

  final int index;
  final String batchId;
  final String name;
  final String batchNo;
  final int sentMrpPaise;
  final int mrpPaise;
  final int version;

  /// False when only other batch details (batch no., expiry) changed.
  final bool priceChanged;
}

/// A batch without enough stock for the bill.
class StockShort {
  const StockShort({
    required this.batchId,
    required this.name,
    required this.batchNo,
    required this.requested,
    required this.available,
  });

  factory StockShort.fromJson(Map<String, dynamic> j) => StockShort(
        batchId: '${j['batch_id']}',
        name: (j['name'] as String?) ?? '',
        batchNo: (j['batch_no'] as String?) ?? '',
        requested: (j['requested_units'] as num?)?.toInt() ?? 0,
        available: (j['available_units'] as num?)?.toInt() ?? 0,
      );

  final String batchId;
  final String name;
  final String batchNo;
  final int requested;
  final int available;
}

/// A batch that can't be sold any more (deleted, expired or not found).
class UnavailableBatch {
  const UnavailableBatch({
    required this.batchId,
    required this.name,
    required this.batchNo,
    required this.reason,
  });

  factory UnavailableBatch.fromJson(Map<String, dynamic> j) => UnavailableBatch(
        batchId: '${j['batch_id']}',
        name: (j['name'] as String?) ?? '',
        batchNo: (j['batch_no'] as String?) ?? '',
        reason: (j['reason'] as String?) ?? 'not_found',
      );

  final String batchId;
  final String name;
  final String batchNo;

  /// expired | deleted | not_found
  final String reason;
}

/// What happened to POST /bills.
sealed class BillResult {
  const BillResult();
}

class BillCreated extends BillResult {
  const BillCreated(this.bill, this.stock, {this.replayed = false});
  final Bill bill;

  /// New stock of the batches sold: batch id -> units.
  final Map<String, int> stock;

  /// A retry of a bill the server had already created.
  final bool replayed;
}

class BillPricesChanged extends BillResult {
  const BillPricesChanged(this.lines);
  final List<StalePrice> lines;
}

class BillStockShort extends BillResult {
  const BillStockShort(this.lines);
  final List<StockShort> lines;
}

class BillBatchesUnavailable extends BillResult {
  const BillBatchesUnavailable(this.lines);
  final List<UnavailableBatch> lines;
}

/// No connection (or no answer): the bill may or may not exist, so a retry
/// must reuse the same bill id.
class BillOffline extends BillResult {
  const BillOffline();
}

class BillFailed extends BillResult {
  const BillFailed(this.status, this.message);
  final int status;
  final String message;
}

/// A value from the server, or why there isn't one.
class ApiOutcome<T> {
  const ApiOutcome.ok(T this.value)
      : status = 200,
        message = null;
  const ApiOutcome.failed(this.status, this.message) : value = null;

  final T? value;
  final int status;
  final String? message;

  bool get isOk => value != null;
  bool get isOffline => status == 0;
}

/// GST bills on the server: create (with the price re-check), list, view,
/// cancel; and the shop's invoice details.
class BillingApi {
  BillingApi([ApiClient? api, this.onUnauthorized]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Called with the token when the server answers 401 (it no longer accepts
  /// this login), so the app signs out ([AuthService.sessionRejected]). Not
  /// called when offline or on other errors; those only show a message.
  void Function(String token)? onUnauthorized;

  ({int status, Map<String, dynamic>? body}) _checked(
      String token, ({int status, Map<String, dynamic>? body}) r) {
    if (r.status == 401) onUnauthorized?.call(token);
    return r;
  }

  Future<BillResult> create(String token, Map<String, Object?> body) async {
    final ({int status, Map<String, dynamic>? body}) r = _checked(
        token,
        await _api.postResult('/bills', Map<String, dynamic>.from(body),
            token: token, timeout: const Duration(seconds: 20)));
    final Map<String, dynamic> b = r.body ?? <String, dynamic>{};
    List<Map<String, dynamic>> lines() => <Map<String, dynamic>>[
          for (final Object? l in (b['lines'] as List<dynamic>?) ?? <dynamic>[])
            Map<String, dynamic>.from(l! as Map),
        ];

    if (r.status == 0) return const BillOffline();
    if ((r.status == 200 || r.status == 201) && b['bill'] is Map) {
      return BillCreated(
        Bill.fromJson(Map<String, dynamic>.from(b['bill'] as Map)),
        _stock(b['batches']),
        replayed: b['replayed'] == true,
      );
    }
    if (r.status == 409 && b['error'] == 'price_changed') {
      return BillPricesChanged(lines().map(StalePrice.fromJson).toList());
    }
    if (r.status == 422 && b['error'] == 'insufficient_stock') {
      return BillStockShort(lines().map(StockShort.fromJson).toList());
    }
    if (r.status == 422 && b['error'] == 'batch_unavailable') {
      return BillBatchesUnavailable(lines().map(UnavailableBatch.fromJson).toList());
    }
    return BillFailed(r.status, errorMessage(r.status, b));
  }

  Future<ApiOutcome<BillPage>> list(String token,
      {DateTime? from, DateTime? to, String? query, int page = 1, int perPage = 30}) async {
    final ({int status, Map<String, dynamic>? body}) r = _checked(
        token,
        await _api.getResult('/bills', token: token, query: <String, String>{
          if (from != null) 'from': ymd(from),
          if (to != null) 'to': ymd(to),
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          'page': '$page',
          'per_page': '$perPage',
        }));
    if (r.status == 200 && r.body != null) return ApiOutcome<BillPage>.ok(BillPage.fromJson(r.body!));
    return ApiOutcome<BillPage>.failed(r.status, errorMessage(r.status, r.body));
  }

  Future<ApiOutcome<Bill>> get(String token, String id) async {
    final ({int status, Map<String, dynamic>? body}) r =
        _checked(token, await _api.getResult('/bills/$id', token: token));
    final Object? bill = r.body?['bill'];
    if (r.status == 200 && bill is Map) {
      return ApiOutcome<Bill>.ok(Bill.fromJson(Map<String, dynamic>.from(bill)));
    }
    return ApiOutcome<Bill>.failed(r.status, errorMessage(r.status, r.body));
  }

  /// Cancel a bill; the outcome carries the bill and the batches' new stock.
  Future<ApiOutcome<(Bill, Map<String, int>)>> cancel(String token, String id,
      {String? reason, String? deviceId}) async {
    final ({int status, Map<String, dynamic>? body}) r = _checked(
        token,
        await _api.postResult(
            '/bills/$id/cancel',
            <String, dynamic>{
              if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
              'device_id': ?deviceId,
            },
            token: token,
            timeout: const Duration(seconds: 20)));
    final Object? bill = r.body?['bill'];
    if (r.status == 200 && bill is Map) {
      return ApiOutcome<(Bill, Map<String, int>)>.ok(
          (Bill.fromJson(Map<String, dynamic>.from(bill)), _stock(r.body?['batches'])));
    }
    return ApiOutcome<(Bill, Map<String, int>)>.failed(r.status, errorMessage(r.status, r.body));
  }

  Future<ApiOutcome<ShopProfile>> shop(String token) async {
    final ({int status, Map<String, dynamic>? body}) r =
        _checked(token, await _api.currentShop(token));
    return _shopOutcome(r);
  }

  Future<ApiOutcome<ShopProfile>> updateShop(String token, Map<String, Object?> changes) async {
    final ({int status, Map<String, dynamic>? body}) r = _checked(
        token, await _api.updateShop(token, Map<String, dynamic>.from(changes)));
    return _shopOutcome(r);
  }

  ApiOutcome<ShopProfile> _shopOutcome(({int status, Map<String, dynamic>? body}) r) {
    final Object? shop = r.body?['shop'];
    if (r.status == 200 && shop is Map) {
      return ApiOutcome<ShopProfile>.ok(ShopProfile.fromJson(Map<String, dynamic>.from(shop)));
    }
    return ApiOutcome<ShopProfile>.failed(r.status, errorMessage(r.status, r.body));
  }

  static Map<String, int> _stock(Object? raw) => <String, int>{
        for (final Object? s in (raw as List<dynamic>?) ?? <dynamic>[])
          if (s is Map) '${s['batch_id']}': (s['qty_units'] as num?)?.toInt() ?? 0,
      };

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A message for the user from an error response.
  static String errorMessage(int status, Map<String, dynamic>? body) {
    if (status == 0) return 'No internet connection.';
    if (status == 401) return 'Your session has expired. Please log in again.';
    final Object? errors = body?['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final Object? first = errors.values.first;
      if (first is List && first.isNotEmpty) return '${first.first}';
    }
    final Object? message = body?['message'];
    if (message is String && message.isNotEmpty) return message;
    return 'Something went wrong (error $status). Please try again.';
  }
}
