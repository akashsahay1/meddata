import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'settings_service.dart';

/// Email auth via the backend's custom Bearer-token API (no Sanctum).
/// Persists the token + basic profile locally so the app stays usable offline
/// after the first successful login.
class AuthService extends ChangeNotifier {
  static const String _kToken = 'auth_token';
  static const String _kEmail = 'auth_email';
  static const String _kName = 'auth_name';

  final SettingsService _settings;
  final ApiClient _api;
  final String deviceId;

  String? _token;
  String? _email;
  String? _name;

  AuthService(this._settings, this.deviceId, [ApiClient? api])
      : _api = api ?? ApiClient();

  String? get token => _token;
  String? get email => _email;
  String? get name => _name;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _token = p.getString(_kToken);
    _email = p.getString(_kEmail);
    _name = p.getString(_kName);
  }

  Future<void> _persist() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (_token == null) {
      await p.remove(_kToken);
      await p.remove(_kEmail);
      await p.remove(_kName);
    } else {
      await p.setString(_kToken, _token!);
      await p.setString(_kEmail, _email ?? '');
      await p.setString(_kName, _name ?? '');
    }
  }

  void _applyEntitlement(Map<String, dynamic>? ent) {
    if (ent == null) return;
    final String? source = ent['source'] as String?;
    final bool paid =
        source == 'razorpay' || source == 'manual' || source == 'coupon';
    _settings.setPremium(paid && (ent['premium'] as bool? ?? false));
    final dynamic te = ent['trial_ends_at'];
    if (te is String && te.isNotEmpty) {
      _settings.setTrialEndsAt(DateTime.tryParse(te)?.toLocal());
    }
  }

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.register(
      name: name,
      email: email,
      password: password,
      phone: phone,
      deviceId: deviceId,
    );
    return _handleAuthResult(r);
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api.login(
      email: email,
      password: password,
      deviceId: deviceId,
    );
    return _handleAuthResult(r);
  }

  String? _handleAuthResult(({int status, Map<String, dynamic>? body}) r) {
    if (r.status == 0) return 'No internet connection. Please try again.';
    final Map<String, dynamic>? b = r.body;
    if (r.status >= 200 && r.status < 300 && b != null && b['token'] != null) {
      _token = b['token'] as String;
      final Map<String, dynamic>? user =
          (b['user'] as Map?)?.cast<String, dynamic>();
      _email = user?['email'] as String?;
      _name = user?['name'] as String?;
      _applyEntitlement((b['entitlement'] as Map?)?.cast<String, dynamic>());
      _persist();
      notifyListeners();
      return null;
    }
    return _errorFrom(b) ?? 'Something went wrong. Please try again.';
  }

  /// Refresh profile + entitlement from the server (best-effort).
  Future<void> refreshMe() async {
    if (!isLoggedIn) return;
    final Map<String, dynamic>? me = await _api.me(_token!);
    if (me == null) return;
    final Map<String, dynamic>? user =
        (me['user'] as Map?)?.cast<String, dynamic>();
    if (user != null) {
      _email = user['email'] as String? ?? _email;
      _name = user['name'] as String? ?? _name;
    }
    _applyEntitlement((me['entitlement'] as Map?)?.cast<String, dynamic>());
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    final String? t = _token;
    _token = null;
    _email = null;
    _name = null;
    await _persist();
    notifyListeners();
    if (t != null) await _api.logout(t); // best-effort server revoke
  }

  Future<String?> forgotPassword(String email) async {
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.forgotPassword(email);
    if (r.status == 0) return 'No internet connection. Please try again.';
    if (r.status >= 200 && r.status < 300) return null;
    return _errorFrom(r.body) ?? 'Could not send reset code.';
  }

  Future<String?> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final ({int status, Map<String, dynamic>? body}) r = await _api
        .resetPassword(email: email, code: code, password: password);
    if (r.status == 0) return 'No internet connection. Please try again.';
    if (r.status >= 200 && r.status < 300) return null;
    return _errorFrom(r.body) ?? 'Invalid or expired code.';
  }

  String? _errorFrom(Map<String, dynamic>? body) {
    if (body == null) return null;
    if (body['message'] is String) return body['message'] as String;
    // Laravel validation errors: { errors: { field: [msg] } }
    final Map<String, dynamic>? errors =
        (body['errors'] as Map?)?.cast<String, dynamic>();
    if (errors != null && errors.isNotEmpty) {
      final dynamic first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    return null;
  }
}
