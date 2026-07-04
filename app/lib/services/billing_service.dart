import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/constants.dart';
import 'api_client.dart';
import 'settings_service.dart';

/// Wraps Google Play Billing via in_app_purchase and reconciles entitlement
/// with the Laravel backend. Entitlement is cached in settings for offline use.
class BillingService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final SettingsService _settings;
  final ApiClient _api;
  final String deviceId;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> products = <ProductDetails>[];
  bool available = false;

  static const Set<String> _productIds = <String>{
    AppConstants.productMonthly,
    AppConstants.productYearly,
    AppConstants.productLifetime,
  };

  BillingService(this._settings, this.deviceId, [ApiClient? api])
      : _api = api ?? ApiClient();

  Future<void> init() async {
    available = await _iap.isAvailable();
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => debugPrint('purchaseStream error: $e'),
    );
    if (available) {
      final ProductDetailsResponse resp =
          await _iap.queryProductDetails(_productIds);
      products = resp.productDetails;
    }
    // Reconcile cached entitlement with the backend when online.
    await refreshEntitlement();
  }

  ProductDetails? productFor(String id) {
    for (final ProductDetails p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> buy(ProductDetails product) async {
    final PurchaseParam param = PurchaseParam(productDetails: product);
    if (product.id == AppConstants.productLifetime) {
      await _iap.buyNonConsumable(purchaseParam: param);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param); // subscriptions
    }
  }

  Future<void> restore() async => _iap.restorePurchases();

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final bool ok = await _verify(purchase);
        if (ok) await _settings.setPremium(true);
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<bool> _verify(PurchaseDetails purchase) async {
    final Map<String, dynamic>? result = await _api.verifyPurchase(
      deviceId: deviceId,
      productId: purchase.productID,
      purchaseToken:
          purchase.verificationData.serverVerificationData,
    );
    // If backend is unreachable, optimistically unlock (client cached) and
    // let the next refresh reconcile. Prevents paying users being locked out.
    if (result == null) return true;
    return (result['status'] as String?) == 'active' ||
        (result['premium'] as bool?) == true;
  }

  /// Pull latest entitlement from backend; update cache if we get an answer.
  Future<void> refreshEntitlement() async {
    final Map<String, dynamic>? ent = await _api.fetchEntitlement(deviceId);
    if (ent == null) return; // stay with cached value offline
    final bool premium = (ent['premium'] as bool?) ??
        ((ent['status'] as String?) == 'active');
    await _settings.setPremium(premium);
  }

  void dispose() => _sub?.cancel();
}
