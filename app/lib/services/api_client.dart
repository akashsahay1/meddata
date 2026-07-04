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

  /// Remote config: free-tier limit, warning days, and plan list for paywall.
  Future<Map<String, dynamic>?> fetchConfig() => _get('/config');

  /// Current entitlement for a device.
  Future<Map<String, dynamic>?> fetchEntitlement(String deviceId) =>
      _get('/entitlement', query: <String, String>{'device_id': deviceId});

  /// Verify a Google Play purchase token server-side.
  Future<Map<String, dynamic>?> verifyPurchase({
    required String deviceId,
    required String productId,
    required String purchaseToken,
  }) =>
      _post('/purchase/verify', <String, dynamic>{
        'device_id': deviceId,
        'product_id': productId,
        'purchase_token': purchaseToken,
      });

  /// Register an anonymous device (no login needed for free users).
  Future<Map<String, dynamic>?> registerDevice(String deviceId) =>
      _post('/register-device', <String, dynamic>{'device_id': deviceId});
}
