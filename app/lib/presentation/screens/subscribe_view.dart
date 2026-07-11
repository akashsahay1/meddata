import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/formatters.dart';
import '../../data/models/subscription_plan.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

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

  /// Fallback feature checklist for plans that ship without their own list.
  static const List<String> _defaultFeatures = <String>[
    'Track unlimited medicines',
    'Expiry & low-stock alerts',
    'Reports & analytics',
    'Secure cloud backup & restore',
    'Export to CSV & PDF',
    'Priority support',
  ];

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
    final String? token = context.read<AuthService>().token;

    final Map<String, dynamic>? order =
        await sub.createOrder(plan.id, _couponApplied, token: token);
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
        token: token,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        await context.read<AuthService>().refreshMe();
        if (!mounted) return;
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
        'theme': <String, dynamic>{'color': '#0E4D4A'},
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
    final String? token = context.read<AuthService>().token;
    final bool ok = await sub.verifyPayment(
      planId: plan.id,
      orderId: r.orderId ?? '',
      paymentId: r.paymentId ?? '',
      signature: r.signature ?? '',
      couponCode: _couponApplied,
      token: token,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await context.read<AuthService>().refreshMe();
      if (!mounted) return;
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

  void _selectPlan(SubscriptionPlan p) {
    setState(() {
      _selected = p;
      _couponResult = null; // re-validate coupon for the new plan
      _couponApplied = null;
      _coupon.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final String cur = settings.currency;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_plans.isEmpty) {
      return _errorState();
    }

    final SubscriptionPlan? plan = _selected;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            children: <Widget>[
              _hero(settings),
              const SizedBox(height: 22),
              if (_plans.length > 1) ...<Widget>[
                _planToggle(cur),
                const SizedBox(height: 18),
              ],
              if (plan != null) _proCard(plan, cur),
              const SizedBox(height: 16),
              _couponField(),
              const SizedBox(height: 16),
              const Text(
                'Payments are processed securely by Razorpay. Your medicine '
                'data always stays on your device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        _bottomBar(cur),
      ],
    );
  }

  // -- Hero ------------------------------------------------------------------

  Widget _hero(SettingsService settings) {
    final String trialLine = settings.isTrialActive
        ? (settings.trialDaysLeft <= 1
            ? 'Keep expiry & low-stock alerts running after your last trial day'
            : 'Keep expiry & low-stock alerts running after your '
                '${settings.trialDaysLeft}-day trial')
        : 'Keep expiry & low-stock alerts running with unlimited tracking';
    return Column(
      children: <Widget>[
        const BrandMark(size: 44),
        const SizedBox(height: 16),
        const Text(
          'Unlock Meddata Pro',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          trialLine,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  // -- Plan toggle -----------------------------------------------------------

  Widget _planToggle(String cur) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.page,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _plans
              .map((SubscriptionPlan p) => _toggleSegment(p))
              .toList(),
        ),
      ),
    );
  }

  Widget _toggleSegment(SubscriptionPlan p) {
    final bool selected = _selected?.id == p.id;
    final bool hasBadge = p.badge != null && p.badge!.isNotEmpty;
    return GestureDetector(
      onTap: () => _selectPlan(p),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x140A302E),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              p.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.ink : AppColors.muted,
              ),
            ),
            if (hasBadge) ...<Widget>[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  p.badge!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -- Pro card --------------------------------------------------------------

  Widget _proCard(SubscriptionPlan plan, String cur) {
    final List<String> features =
        plan.features.isNotEmpty ? plan.features : _defaultFeatures;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.greenDarkest,
        borderRadius: BorderRadius.circular(AppRadii.cardLg),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xB30A302E),
            blurRadius: 44,
            offset: Offset(0, 20),
            spreadRadius: -24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text(
                'Meddata Pro',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
              if (plan.isBestValue)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: const Text(
                    'MOST POPULAR',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.orangeLight,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                Fmt.money(plan.price, symbol: cur),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                plan.periodLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onDarkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _priceSub(plan),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onDarkFaint,
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 18),
            color: Colors.white.withValues(alpha: 0.1),
          ),
          ...features.map(_featureRow),
        ],
      ),
    );
  }

  String _priceSub(SubscriptionPlan p) {
    switch (p.period) {
      case 'yearly':
        return 'Billed annually, cancel anytime';
      case 'monthly':
        return 'Billed monthly, cancel anytime';
      case 'lifetime':
        return 'One-time payment, yours forever';
      default:
        return 'Cancel anytime';
    }
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 14, color: AppColors.orange),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Coupon ----------------------------------------------------------------

  Widget _couponField() {
    final bool applied = _couponApplied != null;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 8),
          Icon(
            Icons.local_offer_outlined,
            size: 18,
            color: applied ? AppColors.statusGreen : AppColors.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              enabled: !applied,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'Have a coupon code?',
              ),
            ),
          ),
          const SizedBox(width: 8),
          applied
              ? TextButton(
                  onPressed: () => setState(() {
                    _couponApplied = null;
                    _couponResult = null;
                    _coupon.clear();
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.statusGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Applied'),
                )
              : TextButton(
                  onPressed: _busy ? null : _applyCoupon,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Apply'),
                ),
        ],
      ),
    );
  }

  // -- Sticky bottom bar -----------------------------------------------------

  Widget _bottomBar(String cur) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _subscribe,
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text('Continue · ${Fmt.money(_payable, symbol: cur)}'),
        ),
      ),
    );
  }

  // -- Error state -----------------------------------------------------------

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text(
              'Could not load plans',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              child: SecondaryButton(label: 'Retry', onPressed: _loadPlans),
            ),
          ],
        ),
      ),
    );
  }
}
