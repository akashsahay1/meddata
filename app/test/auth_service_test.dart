import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_stock/services/api_client.dart';
import 'package:med_stock/services/auth_service.dart';
import 'package:med_stock/services/settings_service.dart';
import 'package:med_stock/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform's secure store.
class _MemoryTokenStore implements TokenStore {
  String? value;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    if (failWrites) throw Exception('keystore unavailable');
    value = token;
  }

  @override
  Future<void> delete() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryTokenStore store;
  late SettingsService settings;

  /// An app launch with [prefs] on disk; [server] answers every request.
  Future<AuthService> launch(Map<String, Object> prefs,
      {Future<http.Response> Function(http.Request)? server}) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = SettingsService();
    await settings.init();
    final AuthService auth = AuthService(
      settings,
      'dev-1',
      ApiClient(MockClient(server ?? (_) async => http.Response('{}', 500))),
      store,
    );
    await auth.init();
    return auth;
  }

  setUp(() => store = _MemoryTokenStore());

  group('token storage', () {
    test('moves a token left in shared_preferences to secure storage',
        () async {
      final AuthService auth = await launch(
          <String, Object>{'auth_token': 'tok-old', 'auth_email': 'a@x.in'});

      expect(auth.token, 'tok-old');
      expect(store.value, 'tok-old');
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.containsKey('auth_token'), isFalse);

      // The next launch reads it from secure storage.
      final AuthService next = AuthService(settings, 'dev-1', null, store);
      await next.init();
      expect(next.token, 'tok-old');
      expect(next.email, 'a@x.in');
    });

    test('keeps the plain copy while secure storage fails', () async {
      store.failWrites = true;
      final AuthService auth =
          await launch(<String, Object>{'auth_token': 'tok-old'});

      expect(auth.isLoggedIn, isTrue);
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getString('auth_token'), 'tok-old');
    });

    test('ignores a token left in secure storage by an earlier install',
        () async {
      store.value = 'tok-stale'; // the iOS Keychain outlives an uninstall
      final AuthService auth = await launch(<String, Object>{});

      expect(auth.isLoggedIn, isFalse);
    });

    test('login saves the token in secure storage only', () async {
      final AuthService auth = await launch(<String, Object>{},
          server: (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'token': 'tok-new',
                'user': <String, Object?>{'email': 'a@x.in', 'name': 'A'},
                'entitlement': <String, Object?>{
                  'premium': true,
                  'source': 'trial',
                  'trial_ends_at': null,
                },
              }),
              200));

      expect(await auth.login(email: 'a@x.in', password: 'secret123'), isNull);
      expect(store.value, 'tok-new');
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.getKeys().where((String k) => p.get(k) == 'tok-new'), isEmpty);
    });
  });

  group('refreshMe', () {
    Map<String, Object> signedIn() => <String, Object>{
          'auth_token_secure': true,
          'auth_email': 'a@x.in',
          'cached_premium': true,
        };

    test('signs out on a 401', () async {
      store.value = 'tok-revoked';
      final AuthService auth = await launch(signedIn(),
          server: (_) async => http.Response(
              jsonEncode(<String, Object?>{'message': 'Unauthenticated'}),
              401));
      expect(auth.isLoggedIn, isTrue);

      await auth.refreshMe();

      expect(auth.isLoggedIn, isFalse);
      expect(store.value, isNull);
      expect(settings.isPremium, isFalse);
      final SharedPreferences p = await SharedPreferences.getInstance();
      expect(p.containsKey('auth_token_secure'), isFalse);
      expect(p.containsKey('auth_email'), isFalse);
    });

    test('stays signed in when offline or the server fails', () async {
      store.value = 'tok-good';
      Object failure = http.ClientException('offline');
      final AuthService auth = await launch(signedIn(), server: (_) async {
        final Object f = failure;
        if (f is http.Response) return f;
        throw f;
      });

      await auth.refreshMe(); // no network
      failure = http.Response('<h1>Bad gateway</h1>', 502);
      await auth.refreshMe();
      failure = http.Response('{"message":"Server Error"}', 500);
      await auth.refreshMe();

      expect(auth.isLoggedIn, isTrue);
      expect(store.value, 'tok-good');
      expect(settings.isPremium, isTrue);
    });
  });

  test('only a real Razorpay key counts for checkout', () {
    expect(SubscriptionService.isRealKey(''), isFalse);
    expect(SubscriptionService.isRealKey('rzp_test_dev'), isFalse);
    expect(SubscriptionService.isRealKey('rzp_test_AbC123'), isTrue);
    expect(SubscriptionService.isRealKey('rzp_live_AbC123'), isTrue);
  });
}
