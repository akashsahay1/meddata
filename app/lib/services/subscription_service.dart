import 'package:flutter/foundation.dart';

import '../data/models/subscription_plan.dart';
import 'api_client.dart';
import 'settings_service.dart';

/// Talks to the Laravel backend for the trial, plans, coupons and Razorpay
/// order/verify flow. The Razorpay checkout UI itself lives in the paywall
/// screen (needs widget lifecycle); this service only does the API calls and
/// keeps the cached entitlement (premium + trial) in SettingsService.
class SubscriptionService extends ChangeNotifier {
  final SettingsService _settings;
  final ApiClient _api;
  final String deviceId;

  String razorpayKeyId = '';
  int trialDays = 7;

  /// Supplies the current auth Bearer token. The trial/entitlement endpoints
  /// are user-scoped now, so they require a token; wired from AuthService in
  /// main.dart. Returns null when the user is not logged in.
  String? Function()? tokenProvider;

  SubscriptionService(this._settings, this.deviceId, [ApiClient? api])
      : _api = api ?? ApiClient();

  /// Register/refresh the trial and pull the current entitlement, then cache it.
  Future<void> refresh() async {
    final String? token = tokenProvider?.call();
    // These endpoints require authentication; nothing to sync when logged out.
    if (token == null || token.isEmpty) return;

    // 1) Ensure the user's one-time trial (idempotent, server-enforced).
    final Map<String, dynamic>? trial =
        await _api.registerTrial(deviceId, token: token);
    if (trial != null) {
      final DateTime? ends = _parseDate(trial['trial_ends_at']);
      if (ends != null) await _settings.setTrialEndsAt(ends);
    }

    // 2) Entitlement = paid OR trial active (backend decides).
    final Map<String, dynamic>? ent =
        await _api.fetchEntitlement(deviceId, token: token);
    if (ent != null) {
      final bool paid = (ent['source'] as String?) == 'razorpay' ||
          (ent['source'] as String?) == 'manual' ||
          (ent['source'] as String?) == 'coupon';
      // Cache "paid premium" separately from trial so the lock logic is correct
      // even offline (trial handled locally by trialEndsAt).
      await _settings.setPremium(paid && (ent['premium'] as bool? ?? false));
      final DateTime? tEnds = _parseDate(ent['trial_ends_at']);
      if (tEnds != null) await _settings.setTrialEndsAt(tEnds);
    }
    notifyListeners();
  }

  Future<List<SubscriptionPlan>> fetchPlans() async {
    final Map<String, dynamic>? config = await _api.fetchConfig();
    if (config == null) return <SubscriptionPlan>[];
    razorpayKeyId = (config['razorpay_key_id'] as String?) ?? '';
    trialDays = (config['trial_days'] as num?)?.toInt() ?? 7;
    final List<dynamic> plans = config['plans'] as List<dynamic>? ?? <dynamic>[];
    return plans
        .map((dynamic p) =>
            SubscriptionPlan.fromJson(Map<String, dynamic>.from(p as Map)))
        .where((SubscriptionPlan p) => !p.isFree) // paywall shows paid plans
        .toList();
  }

  Future<Map<String, dynamic>?> validateCoupon(String code, int planId) =>
      _api.validateCoupon(
          code: code, planId: planId, token: tokenProvider?.call());

  Future<Map<String, dynamic>?> createOrder(int planId, String? couponCode,
          {String? token}) =>
      _api.createOrder(
          deviceId: deviceId,
          planId: planId,
          couponCode: couponCode,
          token: token);

  /// Verify a completed Razorpay payment; on success caches premium locally.
  Future<bool> verifyPayment({
    required int planId,
    required String orderId,
    required String paymentId,
    required String signature,
    String? couponCode,
    String? token,
  }) async {
    final Map<String, dynamic>? res = await _api.verifyPayment(
      deviceId: deviceId,
      planId: planId,
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
      couponCode: couponCode,
      token: token,
    );
    final bool ok = (res?['premium'] as bool?) ?? false;
    if (ok) {
      await _settings.setPremium(true);
      notifyListeners();
    }
    return ok;
  }

  DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
