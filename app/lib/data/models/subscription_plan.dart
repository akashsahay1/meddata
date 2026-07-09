/// A subscription plan as served by the backend `/config` endpoint.
class SubscriptionPlan {
  final int id;
  final String productId;
  final String name;
  final double price;
  final String currency;
  final String period; // monthly | yearly | lifetime | free
  final String? badge;
  final bool isBestValue;
  final List<String> features;

  const SubscriptionPlan({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    required this.currency,
    required this.period,
    this.badge,
    this.isBestValue = false,
    this.features = const <String>[],
  });

  bool get isFree => period == 'free' || price <= 0;

  String get periodLabel {
    switch (period) {
      case 'monthly':
        return 'per month';
      case 'yearly':
        return 'per year';
      case 'lifetime':
        return 'one-time';
      default:
        return '';
    }
  }

  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) {
    return SubscriptionPlan(
      id: (j['id'] as num?)?.toInt() ?? 0,
      productId: (j['product_id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      price: ((j['price'] as num?) ?? 0).toDouble(),
      currency: (j['currency'] as String?) ?? 'INR',
      period: (j['period'] as String?) ?? (j['billing_period'] as String?) ?? '',
      badge: j['badge'] as String?,
      isBestValue: (j['is_best_value'] as bool?) ?? false,
      features: (j['features'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
    );
  }
}
