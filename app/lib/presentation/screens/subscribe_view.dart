import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/formatters.dart';
import '../../data/models/subscription_plan.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';

/// The subscribe / paywall content: plans from the backend, coupon apply, and
/// Razorpay checkout. Shared by the (dismissible) UpgradeScreen and the
/// (non-dismissible) LockScreen. Calls [onUnlocked] after a verified payment.
class SubscribeView extends StatefulWidget {
  final VoidCallback? onUnlocked;
  const SubscribeView({super.key, this.onUnlocked});

  @override
  State<SubscribeView> createState() => _SubscribeViewState();
}

class _SubscribeViewState extends State<SubscribeView> {
  final TextEditingController _coupon = TextEditingController();
  late final Razorpay _razorpay;

  List<SubscriptionPlan> _plans = <SubscriptionPlan>[];
  bool _loading = true;
  bool _busy = false;

  SubscriptionPlan? _selected;
  Map<String, dynamic>? _couponResult; // {valid, discount, final_amount, message}
  String? _couponApplied;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _loadPlans();
  }

  @override
  void dispose() {
    _razorpay.clear();
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    final SubscriptionService sub = context.read<SubscriptionService>();
    final List<SubscriptionPlan> plans = await sub.fetchPlans();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _selected = plans.isEmpty
          ? null
          : plans.firstWhere((SubscriptionPlan p) => p.isBestValue,
              orElse: () => plans.first);
      _loading = false;
    });
  }

  double get _payable {
    if (_selected == null) return 0;
    if (_couponResult != null && (_couponResult!['valid'] as bool? ?? false)) {
      return ((_couponResult!['final_amount'] as num?) ?? _selected!.price)
          .toDouble();
    }
    return _selected!.price;
  }

  Future<void> _applyCoupon() async {
    if (_selected == null || _coupon.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final SubscriptionService sub = context.read<SubscriptionService>();
    final Map<String, dynamic>? res =
        await sub.validateCoupon(_coupon.text.trim(), _selected!.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _couponResult = res;
      _couponApplied = (res?['valid'] as bool? ?? false)
          ? _coupon.text.trim().toUpperCase()
          : null;
    });
    _snack(res == null
        ? 'Could not validate coupon (offline?)'
        : (res['message'] as String?) ??
            ((res['valid'] as bool? ?? false) ? 'Coupon applied' : 'Invalid coupon'));
  }

  Future<void> _subscribe() async {
    final SubscriptionPlan? plan = _selected;
    if (plan == null) return;
    setState(() => _busy = true);
    final SubscriptionService sub = context.read<SubscriptionService>();

    final Map<String, dynamic>? order =
        await sub.createOrder(plan.id, _couponApplied);
    if (!mounted) return;
    if (order == null) {
      setState(() => _busy = false);
      _snack('Could not start payment. Check your connection and try again.');
      return;
    }

    final String keyId = (order['key_id'] as String?) ?? sub.razorpayKeyId;
    final String orderId = (order['order_id'] as String?) ?? '';
    final int amountPaise = (order['amount'] as num?)?.toInt() ?? 0;

    // Dev fallback: no real Razorpay keys configured → simulate a paid order so
    // the whole flow is testable. Real keys → open the real Razorpay checkout.
    final bool devMode = keyId.isEmpty || keyId == 'rzp_test_dev';
    if (devMode) {
      final bool ok = await sub.verifyPayment(
        planId: plan.id,
        orderId: orderId,
        paymentId: 'pay_dev_${DateTime.now().millisecondsSinceEpoch}',
        signature: 'dev',
        couponCode: _couponApplied,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        _snack('Payment successful (test mode). Premium unlocked.');
        widget.onUnlocked?.call();
      } else {
        _snack('Test payment could not be verified.');
      }
      return;
    }

    try {
      _razorpay.open(<String, dynamic>{
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': 'Meddata',
        'description': plan.name,
        'prefill': <String, dynamic>{'contact': '', 'email': ''},
        'theme': <String, dynamic>{'color': '#000000'},
      });
    } catch (e) {
      setState(() => _busy = false);
      _snack('Could not open checkout: $e');
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    final SubscriptionPlan? plan = _selected;
    if (plan == null) return;
    final SubscriptionService sub = context.read<SubscriptionService>();
    final bool ok = await sub.verifyPayment(
      planId: plan.id,
      orderId: r.orderId ?? '',
      paymentId: r.paymentId ?? '',
      signature: r.signature ?? '',
      couponCode: _couponApplied,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _snack('Payment successful. Premium unlocked.');
      widget.onUnlocked?.call();
    } else {
      _snack('Payment could not be verified. If money was deducted, contact support.');
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    if (!mounted) return;
    setState(() => _busy = false);
    _snack('Payment failed: ${r.message ?? 'cancelled'}');
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _snack('Selected wallet: ${r.walletName ?? ''}');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final String cur = settings.currency;
    final Color fg = Theme.of(context).colorScheme.onSurface;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off, size: 48),
              const SizedBox(height: 12),
              const Text('Could not load plans',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Check your internet connection and try again.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _loadPlans, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('Premium Features',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...const <String>[
          'Track unlimited medicines',
          'Advanced expiry alerts',
          'Detailed reports & analytics',
          'Secure cloud backup & restore',
          'Export to CSV & PDF',
          'Priority support',
        ].map((String f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: <Widget>[
                const Icon(Icons.check, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(f)),
              ]),
            )),
        const SizedBox(height: 16),
        const Text('Choose Your Plan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ..._plans.map((SubscriptionPlan p) => _planCard(p, cur, fg)),
        const SizedBox(height: 8),
        _couponField(fg),
        const SizedBox(height: 16),
        if (_selected != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('Total payable',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text(Fmt.money(_payable, symbol: cur),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _busy ? null : _subscribe,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Subscribe · ${Fmt.money(_payable, symbol: cur)}'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Payments are processed securely by Razorpay. Your medicine data '
          'always stays on your device.',
          style: TextStyle(fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _planCard(SubscriptionPlan p, String cur, Color fg) {
    final bool selected = _selected?.id == p.id;
    final Color bg = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => setState(() {
          _selected = p;
          _couponResult = null; // re-validate coupon for the new plan
          _couponApplied = null;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? fg : bg,
            border: Border.all(color: fg, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? bg : fg,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(children: <Widget>[
                      Text(p.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: selected ? bg : fg)),
                      if (p.badge != null && p.badge!.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: selected ? bg : fg),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(p.badge!,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: selected ? bg : fg)),
                        ),
                      ],
                    ]),
                    Text(p.periodLabel,
                        style:
                            TextStyle(fontSize: 12, color: selected ? bg : fg)),
                  ],
                ),
              ),
              Text(Fmt.money(p.price, symbol: cur),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: selected ? bg : fg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _couponField(Color fg) {
    final bool applied = _couponApplied != null;
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _coupon,
            textCapitalization: TextCapitalization.characters,
            enabled: !applied,
            decoration: InputDecoration(
              labelText: 'Coupon code',
              prefixIcon: const Icon(Icons.local_offer_outlined),
              suffixIcon: applied
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _couponApplied = null;
                        _couponResult = null;
                        _coupon.clear();
                      }),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: (_busy || applied) ? null : _applyCoupon,
            child: Text(applied ? 'Applied' : 'Apply'),
          ),
        ),
      ],
    );
  }
}
