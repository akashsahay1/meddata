import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'settings_service.dart';

/// Where the Bearer token is kept. The token is as good as the password, so
/// it goes in the platform's secure store, not plain shared_preferences.
/// Tests use an in-memory store.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Keychain on iOS, Keystore-encrypted storage on Android, Credential Manager
/// plus an encrypted file on Windows.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const String _key = 'auth_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    // Readable once the phone has been unlocked after boot (not only while
    // unlocked), and never restored from a backup onto another device.
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Email auth via the backend's custom Bearer-token API (no Sanctum).
/// Persists the token (in [TokenStore]) + basic profile locally so the app
/// stays usable offline after the first successful login.
class AuthService extends ChangeNotifier {
  /// Older builds kept the token here, in plain shared_preferences. It is
  /// moved into the [TokenStore] on first read, then deleted.
  static const String _kLegacyToken = 'auth_token';

  /// Set while the [TokenStore] holds our token. A Keychain item outlives an
  /// uninstall on iOS but shared_preferences don't, so a token stored without
  /// this flag is left over from an earlier install and is ignored.
  static const String _kTokenSaved = 'auth_token_secure';
  static const String _kEmail = 'auth_email';
  static const String _kName = 'auth_name';
  static const String _kAvatar = 'auth_avatar_url';

  final SettingsService _settings;
  final ApiClient _api;
  final TokenStore _tokens;
  final String deviceId;

  String? _token;
  String? _email;
  String? _name;
  String? _avatarUrl;

  AuthService(this._settings, this.deviceId,
      [ApiClient? api, TokenStore? tokens])
      : _api = api ?? ApiClient(),
        _tokens = tokens ?? const SecureTokenStore();

  String? get token => _token;
  String? get email => _email;
  String? get name => _name;
  String? get avatarUrl => _avatarUrl;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  Future<void> init() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    _token = await _loadToken(p);
    _email = p.getString(_kEmail);
    _name = p.getString(_kName);
    final String? avatar = p.getString(_kAvatar);
    _avatarUrl = (avatar == null || avatar.isEmpty) ? null : avatar;
  }

  /// The saved token, if any. One that an older build left in
  /// shared_preferences is moved to the [TokenStore] first; the plain copy is
  /// deleted only once that worked, so a failing store never signs anyone out.
  Future<String?> _loadToken(SharedPreferences p) async {
    final String? legacy = p.getString(_kLegacyToken);
    if (legacy != null && legacy.isNotEmpty) {
      await _saveToken(p, legacy);
      return legacy;
    }
    if (p.getBool(_kTokenSaved) != true) return null;
    try {
      return await _tokens.read();
    } catch (e) {
      debugPrint('[Auth] could not read the saved token: $e');
      return null;
    }
  }

  /// Saves [token] in the [TokenStore] and drops any plain copy. On failure
  /// the token lasts for this session only; it is never stored less safely.
  Future<void> _saveToken(SharedPreferences p, String token) async {
    try {
      await _tokens.write(token);
      await p.setBool(_kTokenSaved, true);
      await p.remove(_kLegacyToken);
    } catch (e) {
      debugPrint('[Auth] could not save the token: $e');
    }
  }

  Future<void> _deleteToken(SharedPreferences p) async {
    await p.remove(_kTokenSaved);
    await p.remove(_kLegacyToken);
    try {
      await _tokens.delete();
    } catch (e) {
      debugPrint('[Auth] could not delete the saved token: $e');
    }
  }

  /// Caches the profile so it shows offline; cleared once signed out.
  Future<void> _persistProfile() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    if (_token == null) {
      await p.remove(_kEmail);
      await p.remove(_kName);
      await p.remove(_kAvatar);
    } else {
      await p.setString(_kEmail, _email ?? '');
      await p.setString(_kName, _name ?? '');
      await p.setString(_kAvatar, _avatarUrl ?? '');
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

  Future<String?> _handleAuthResult(
      ({int status, Map<String, dynamic>? body}) r) async {
    if (r.status == 0) return 'No internet connection. Please try again.';
    final Map<String, dynamic>? b = r.body;
    if (r.status >= 200 && r.status < 300 && b != null && b['token'] != null) {
      _token = b['token'] as String;
      final Map<String, dynamic>? user =
          (b['user'] as Map?)?.cast<String, dynamic>();
      _email = user?['email'] as String?;
      _name = user?['name'] as String?;
      _avatarUrl = user?['avatar_url'] as String?;
      _applyEntitlement((b['entitlement'] as Map?)?.cast<String, dynamic>());
      await _saveToken(await SharedPreferences.getInstance(), _token!);
      await _persistProfile();
      notifyListeners();
      return null;
    }
    return _errorFrom(b) ?? 'Something went wrong. Please try again.';
  }

  /// Refresh profile + entitlement from the server (best-effort). Signs out
  /// only on a definitive 401, i.e. the server no longer accepts this token
  /// (logged out elsewhere, password changed or reset). Being offline, a
  /// timeout or a server error keeps the session, as the app works offline.
  Future<void> refreshMe() async {
    if (!isLoggedIn) return;
    final String token = _token!;
    final ({int status, Map<String, dynamic>? body}) r = await _api.me(token);
    if (r.status == 401) {
      // Unless someone signed in again while the request was in flight.
      if (_token == token) await _signOutLocally();
      return;
    }
    final Map<String, dynamic>? me = r.status == 200 ? r.body : null;
    if (me == null) return;
    final Map<String, dynamic>? user =
        (me['user'] as Map?)?.cast<String, dynamic>();
    if (user != null) {
      _email = user['email'] as String? ?? _email;
      _name = user['name'] as String? ?? _name;
      _avatarUrl = user['avatar_url'] as String?;
    }
    _applyEntitlement((me['entitlement'] as Map?)?.cast<String, dynamic>());
    await _persistProfile();
    notifyListeners();
  }

  Future<void> logout() async {
    final String? t = _token;
    await _signOutLocally();
    if (t != null) await _api.logout(t); // best-effort server revoke
  }

  /// Forgets the session on this device: the token, the cached profile and
  /// the cached plan (the next account to sign in gets its own from the server).
  Future<void> _signOutLocally() async {
    _token = null;
    _email = null;
    _name = null;
    _avatarUrl = null;
    await _deleteToken(await SharedPreferences.getInstance());
    await _persistProfile();
    await _settings.setPremium(false);
    await _settings.setTrialEndsAt(null);
    notifyListeners();
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

  /// Update the signed-in user's name and/or email. Returns null on success,
  /// or a user-facing error message on failure.
  Future<String?> updateProfile({String? name, String? email}) async {
    if (!isLoggedIn) return 'You are not signed in.';
    final ({int status, Map<String, dynamic>? body}) r = await _api
        .updateProfile(token: _token!, name: name, email: email);
    if (r.status == 0) return 'No internet connection. Please try again.';
    if (r.status >= 200 && r.status < 300) {
      final Map<String, dynamic>? user =
          (r.body?['user'] as Map?)?.cast<String, dynamic>();
      if (user != null) {
        _name = user['name'] as String? ?? _name;
        _email = user['email'] as String? ?? _email;
      }
      await _persistProfile();
      notifyListeners();
      return null;
    }
    return _errorFrom(r.body) ?? 'Could not update profile.';
  }

  /// Upload a new profile photo from [filePath]. Returns null on success, or
  /// a user-facing error message on failure.
  Future<String?> uploadAvatar(String filePath) async {
    if (!isLoggedIn) return 'You are not signed in.';
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.uploadAvatar(token: _token!, filePath: filePath);
    return _applyAvatarResult(r, 'Could not upload photo.');
  }

  /// Remove the profile photo. Returns null on success, or an error message.
  Future<String?> removeAvatar() async {
    if (!isLoggedIn) return 'You are not signed in.';
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.deleteAvatar(_token!);
    return _applyAvatarResult(r, 'Could not remove photo.');
  }

  Future<String?> _applyAvatarResult(
      ({int status, Map<String, dynamic>? body}) r, String fallback) async {
    if (r.status == 0) return 'No internet connection. Please try again.';
    if (r.status >= 200 && r.status < 300) {
      final Map<String, dynamic>? user =
          (r.body?['user'] as Map?)?.cast<String, dynamic>();
      _avatarUrl = user?['avatar_url'] as String?;
      await _persistProfile();
      notifyListeners();
      return null;
    }
    return _errorFrom(r.body) ?? fallback;
  }

  /// Change the signed-in user's password. Returns null on success, or a
  /// user-facing error message on failure.
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!isLoggedIn) return 'You are not signed in.';
    final ({int status, Map<String, dynamic>? body}) r =
        await _api.changePassword(
      token: _token!,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (r.status == 0) return 'No internet connection. Please try again.';
    if (r.status >= 200 && r.status < 300) return null;
    return _errorFrom(r.body) ?? 'Could not change password.';
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
