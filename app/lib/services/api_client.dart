import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client for the Laravel backend. Every call is best-effort: the app
/// stays fully functional offline, so callers must handle null/failure.
class ApiClient {
  /// Base URL of the Laravel API served by Herd.
  /// Android emulator reaches the host machine via 10.0.2.2.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://med-stock-api.test/api/v1',
  );

  final http.Client _http;
  ApiClient([http.Client? client]) : _http = client ?? http.Client();

  Duration get _timeout => const Duration(seconds: 8);

  Future<Map<String, dynamic>?> _get(String path,
      {Map<String, String>? query}) async {
    try {
      final Uri uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final http.Response res = await _http.get(uri).timeout(_timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body,
      {String? token}) async {
    try {
      final Uri uri = Uri.parse('$baseUrl$path');
      final http.Response res = await _http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Remote config: trial_days, razorpay_key_id, and plan list for the paywall.
  Future<Map<String, dynamic>?> fetchConfig() => _get('/config');

  /// Current entitlement for a device (premium = paid OR trial active).
  Future<Map<String, dynamic>?> fetchEntitlement(String deviceId) =>
      _get('/entitlement', query: <String, String>{'device_id': deviceId});

  /// Register / fetch the 7-day free trial for a device (idempotent).
  Future<Map<String, dynamic>?> registerTrial(String deviceId) =>
      _post('/device/trial', <String, dynamic>{'device_id': deviceId});

  /// Validate a coupon code against a plan → discount + final amount.
  Future<Map<String, dynamic>?> validateCoupon({
    required String code,
    required int planId,
  }) =>
      _post('/coupon/validate', <String, dynamic>{
        'code': code,
        'plan_id': planId,
      });

  /// Create a Razorpay order for a plan (with optional coupon).
  Future<Map<String, dynamic>?> createOrder({
    required String deviceId,
    required int planId,
    String? couponCode,
  }) =>
      _post('/order/create', <String, dynamic>{
        'device_id': deviceId,
        'plan_id': planId,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      });

  /// Verify a completed Razorpay payment and activate the subscription.
  Future<Map<String, dynamic>?> verifyPayment({
    required String deviceId,
    required int planId,
    required String orderId,
    required String paymentId,
    required String signature,
    String? couponCode,
  }) =>
      _post('/payment/verify', <String, dynamic>{
        'device_id': deviceId,
        'plan_id': planId,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      });
}
