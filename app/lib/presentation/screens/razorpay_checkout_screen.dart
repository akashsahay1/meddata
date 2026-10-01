import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';

/// Full-screen WebView that hosts Razorpay Standard Checkout (checkout.js).
///
/// It opens the given [orderId] with [keyId], then bridges the checkout result
/// back to Flutter over a single JavaScript channel named `RZP`.
///
/// Pops with:
///   * a `{paymentId, orderId, signature}` map on a successful payment, or
///   * `null` when the payment failed, the modal was dismissed, or the user
///     closed the screen from the AppBar.
class RazorpayCheckoutScreen extends StatefulWidget {
  const RazorpayCheckoutScreen({
    super.key,
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    this.name = 'Meddata',
    this.description = '',
    this.prefillEmail = '',
    this.prefillContact = '',
  });

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String name;
  final String description;
  final String prefillEmail;
  final String prefillContact;

  @override
  State<RazorpayCheckoutScreen> createState() => _RazorpayCheckoutScreenState();
}

class _RazorpayCheckoutScreenState extends State<RazorpayCheckoutScreen> {
  late final WebViewController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RZP', onMessageReceived: _onMessage)
      ..loadHtmlString(
        _buildHtml(),
        baseUrl: 'https://checkout.razorpay.com',
      );
  }

  void _onMessage(JavaScriptMessage message) {
    if (_handled) return;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      payload = <String, dynamic>{'status': 'failed'};
    }

    final String status = (payload['status'] as String?) ?? 'failed';
    if (status == 'success') {
      _finish(<String, String>{
        'paymentId': (payload['razorpay_payment_id'] as String?) ?? '',
        'orderId': (payload['razorpay_order_id'] as String?) ?? '',
        'signature': (payload['razorpay_signature'] as String?) ?? '',
      });
    } else {
      // 'failed' or 'dismissed' both cancel with no charge.
      _finish(null);
    }
  }

  void _finish(Map<String, String>? result) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(result);
  }

  String _buildHtml() {
    final Map<String, dynamic> options = <String, dynamic>{
      'key': widget.keyId,
      'order_id': widget.orderId,
      'amount': widget.amountPaise,
      'currency': 'INR',
      'name': widget.name,
      'description': widget.description,
      'prefill': <String, String>{
        'email': widget.prefillEmail,
        'contact': widget.prefillContact,
      },
      'theme': <String, String>{'color': '#0E4D4A'},
    };
    // jsonEncode keeps every value safely escaped for embedding in the script.
    final String optionsJson = jsonEncode(options);

    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body {
    margin: 0;
    padding: 0;
    height: 100%;
    background: #DCE4E2;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  .loader {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #66807D;
    font-size: 15px;
    font-weight: 600;
  }
</style>
<script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body>
<div class="loader">Loading secure checkout...</div>
<script>
  function post(obj) {
    try { RZP.postMessage(JSON.stringify(obj)); } catch (e) {}
  }
  function startCheckout() {
    if (typeof Razorpay === 'undefined') {
      post({ status: 'failed', error: 'checkout.js failed to load' });
      return;
    }
    var options = $optionsJson;
    options.handler = function (response) {
      post({
        status: 'success',
        razorpay_payment_id: response.razorpay_payment_id,
        razorpay_order_id: response.razorpay_order_id,
        razorpay_signature: response.razorpay_signature
      });
    };
    options.modal = {
      ondismiss: function () { post({ status: 'dismissed' }); },
      escape: true
    };
    try {
      var rzp = new Razorpay(options);
      rzp.on('payment.failed', function (response) {
        post({ status: 'failed', error: (response && response.error) ? response.error.description : 'payment failed' });
      });
      rzp.open();
    } catch (e) {
      post({ status: 'failed', error: String(e) });
    }
  }
  window.onload = startCheckout;
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Secure Checkout',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: Colors.white,
          tooltip: 'Cancel',
          onPressed: () => _finish(null),
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
