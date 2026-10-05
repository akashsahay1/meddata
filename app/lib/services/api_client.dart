import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thin client for the Laravel backend. Every call is best-effort: the app
/// stays fully functional offline, so callers must handle null/failure.
class ApiClient {
  /// Base URL of the Laravel API. Defaults to the live backend; override with
  /// `--dart-define=API_BASE_URL=...` for local dev (e.g. an `adb reverse`
  /// tunnel at `http://127.0.0.1:8000/api/v1`).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://meddata.akashxdev.com/api/v1',
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
      debugPrint('[ApiClient] POST $path -> ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[ApiClient] POST $path failed: $e');
    }
    return null;
  }

  /// Prefix-search the medicines master list for name autocomplete.
  /// Returns the `results` list (empty on any failure, empty response, or a
  /// query shorter than the backend's 2-char minimum).
  Future<List<Map<String, dynamic>>> searchMedicines(String q,
      {String? token}) async {
    final Map<String, dynamic>? body = await _get(
      '/medicines/search',
      query: <String, String>{'q': q},
      token: token,
    );
    final Object? results = body?['results'];
    if (results is List) {
      return results.whereType<Map<String, dynamic>>().toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// Look a barcode up in the medicines master list. Returns the first match,
  /// or null when there is none or the server can't be reached.
  Future<Map<String, dynamic>?> lookupBarcode(String barcode,
      {String? token}) async {
    final Map<String, dynamic>? body = await _get(
      '/medicines/search',
      query: <String, String>{'barcode': barcode},
      token: token,
    );
    final Object? results = body?['results'];
    if (results is List && results.isNotEmpty) {
      final Object? first = results.first;
      if (first is Map<String, dynamic>) return first;
    }
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

  /// Current user + entitlement, with the HTTP status (0 = network failure)
  /// so a rejected token (401) can be told apart from being offline.
  Future<({int status, Map<String, dynamic>? body})> me(String token) =>
      getResult('/auth/me', token: token);

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

  /// GET that also returns the HTTP status (0 = network failure).
  Future<({int status, Map<String, dynamic>? body})> getResult(String path,
      {Map<String, String>? query, String? token, Duration? timeout}) async {
    try {
      final Uri uri =
          Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final http.Response res = await _http.get(uri, headers: <String, String>{
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      }).timeout(timeout ?? _timeout);
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (_) {
      return (status: 0, body: null);
    }
  }

  // ---- Shop + multi-device sync -------------------------------------------

  Future<({int status, Map<String, dynamic>? body})> currentShop(String token) =>
      getResult('/shops/current', token: token);

  Future<({int status, Map<String, dynamic>? body})> syncStatus(String token) =>
      getResult('/sync/status', token: token);

  Future<({int status, Map<String, dynamic>? body})> syncPull(String token,
          {required int since, required String deviceId, int limit = 500}) =>
      getResult('/sync/pull',
          token: token,
          timeout: const Duration(seconds: 30),
          query: <String, String>{
            'since': '$since',
            'limit': '$limit',
            'device_id': deviceId,
          });

  Future<({int status, Map<String, dynamic>? body})> syncPush(String token,
      {required String deviceId,
      required List<Map<String, Object?>> mutations,
      String? platform}) async {
    try {
      final http.Response res = await _http
          .post(
            Uri.parse('$baseUrl/sync/push'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, Object?>{
              'device_id': deviceId,
              'mutations': mutations,
              'platform': ?platform,
            }),
          )
          .timeout(const Duration(seconds: 30));
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (_) {
      return (status: 0, body: null);
    }
  }

  /// Upload (or replace) the profile photo at [filePath] as multipart.
  Future<({int status, Map<String, dynamic>? body})> uploadAvatar({
    required String token,
    required String filePath,
  }) async {
    try {
      final http.MultipartRequest req =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/auth/avatar'))
            ..headers.addAll(<String, String>{
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            })
            ..files.add(await http.MultipartFile.fromPath('avatar', filePath));
      final http.Response res = await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 30)));
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (e) {
      debugPrint('[ApiClient] avatar upload failed: $e');
      return (status: 0, body: null);
    }
  }

  /// Remove the profile photo.
  Future<({int status, Map<String, dynamic>? body})> deleteAvatar(
      String token) async {
    try {
      final http.Response res = await _http.delete(
        Uri.parse('$baseUrl/auth/avatar'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return (status: res.statusCode, body: parsed);
    } catch (_) {
      return (status: 0, body: null);
    }
  }

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

  /// Create a Razorpay order for a plan (with optional coupon). Returns the
  /// HTTP status too: 503 means the server isn't taking payments right now.
  Future<({int status, Map<String, dynamic>? body})> createOrder({
    required String deviceId,
    required int planId,
    String? couponCode,
    String? token,
  }) =>
      postResult('/order/create', <String, dynamic>{
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
