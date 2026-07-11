import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client for the Laravel backend. Every call is best-effort: the app
/// stays fully functional offline, so callers must handle null/failure.
class ApiClient {
  /// Base URL of the Laravel API.
  /// TEMP (dev): points at `php artisan serve` on the Mac's LAN IP so a physical
  /// iPhone on the same Wi-Fi can reach it. Herd's `.test` URL only resolves on
  /// the host machine; `127.0.0.1` on a real device means the phone itself.
  /// Android emulator reaches the host via 10.0.2.2 instead.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.29.220:8000/api/v1',
  );

  final http.Client _http;
  ApiClient([http.Client? client]) : _http = client ?? http.Client();

  Duration get _timeout => const Duration(seconds: 8);

  Future<Map<String, dynamic>?> _get(String path,
      {Map<String, String>? query, String? token}) async {
    try {
      final Uri uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final http.Response res = await _http.get(uri, headers: <String, String>{
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      }).timeout(_timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// POST that also returns the HTTP status so auth flows can distinguish
  /// invalid-credentials (422/401) from network failure (null).
  Future<({int status, Map<String, dynamic>? body})> postResult(
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
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (_) {
      return (status: 0, body: null);
    }
  }

  /// PATCH that also returns the HTTP status (mirrors [postResult]).
  Future<({int status, Map<String, dynamic>? body})> _patchResult(
      String path, Map<String, dynamic> body,
      {String? token}) async {
    try {
      final Uri uri = Uri.parse('$baseUrl$path');
      final http.Response res = await _http
          .patch(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (_) {
      return (status: 0, body: null);
    }
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

  /// Current entitlement for the authenticated user (premium = paid OR trial).
  /// Requires a Bearer token; device_id is sent for reference only.
  Future<Map<String, dynamic>?> fetchEntitlement(String deviceId,
          {String? token}) =>
      _get('/entitlement',
          query: <String, String>{'device_id': deviceId}, token: token);

  /// Ensure the authenticated user's one-time free trial (idempotent).
  /// Requires a Bearer token.
  Future<Map<String, dynamic>?> registerTrial(String deviceId,
          {String? token}) =>
      _post('/device/trial', <String, dynamic>{'device_id': deviceId},
          token: token);

  // ---- Auth (custom Bearer token) ----

  Future<({int status, Map<String, dynamic>? body})> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? deviceId,
  }) =>
      postResult('/auth/register', <String, dynamic>{
        'name': name,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'device_id': ?deviceId,
      });

  Future<({int status, Map<String, dynamic>? body})> login({
    required String email,
    required String password,
    String? deviceId,
  }) =>
      postResult('/auth/login', <String, dynamic>{
        'email': email,
        'password': password,
        'device_id': ?deviceId,
      });

  Future<void> logout(String token) => _post('/auth/logout', <String, dynamic>{},
      token: token);

  Future<Map<String, dynamic>?> me(String token) =>
      _get('/auth/me', token: token);

  Future<({int status, Map<String, dynamic>? body})> forgotPassword(
          String email) =>
      postResult('/auth/forgot-password', <String, dynamic>{'email': email});

  Future<({int status, Map<String, dynamic>? body})> resetPassword({
    required String email,
    required String code,
    required String password,
  }) =>
      postResult('/auth/reset-password', <String, dynamic>{
        'email': email,
        'code': code,
        'password': password,
      });

  /// Update the authenticated user's name and/or email.
  Future<({int status, Map<String, dynamic>? body})> updateProfile({
    required String token,
    String? name,
    String? email,
  }) =>
      _patchResult('/auth/profile', <String, dynamic>{
        'name': ?name,
        'email': ?email,
      }, token: token);

  /// Change the authenticated user's password.
  Future<({int status, Map<String, dynamic>? body})> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) =>
      postResult('/auth/change-password', <String, dynamic>{
        'current_password': currentPassword,
        'password': newPassword,
      }, token: token);

  /// Validate a coupon code against a plan → discount + final amount.
  Future<Map<String, dynamic>?> validateCoupon({
    required String code,
    required int planId,
    String? token,
  }) =>
      _post('/coupon/validate', <String, dynamic>{
        'code': code,
        'plan_id': planId,
      }, token: token);

  /// Create a Razorpay order for a plan (with optional coupon).
  Future<Map<String, dynamic>?> createOrder({
    required String deviceId,
    required int planId,
    String? couponCode,
    String? token,
  }) =>
      _post('/order/create', <String, dynamic>{
        'device_id': deviceId,
        'plan_id': planId,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      }, token: token);

  /// Verify a completed Razorpay payment and activate the subscription.
  Future<Map<String, dynamic>?> verifyPayment({
    required String deviceId,
    required int planId,
    required String orderId,
    required String paymentId,
    required String signature,
    String? couponCode,
    String? token,
  }) =>
      _post('/payment/verify', <String, dynamic>{
        'device_id': deviceId,
        'plan_id': planId,
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      }, token: token);
}
