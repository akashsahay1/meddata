<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Models\User;
use App\Services\OrderPaymentService;
use App\Services\RazorpayService;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;

/**
 * Razorpay checkout in the browser, for the desktop app (which has no
 * in-app WebView). The app creates the order as usual and opens
 * /pay/{order}; Razorpay posts the result to /pay/complete, which verifies
 * the signature on the server and activates the subscription itself. The
 * app then just refreshes the user's entitlement.
 */
class BrowserCheckoutController extends Controller
{
    public function __construct(
        private readonly RazorpayService $razorpay,
        private readonly OrderPaymentService $orders,
    ) {}

    /** GET /pay/{order} — the checkout page for an unpaid order. */
    public function show(string $order): Response
    {
        $payment = Payment::where('razorpay_order_id', $order)->orderByDesc('id')->first();
        if (! $payment || $payment->status === 'paid') {
            return $this->result(false, $payment ? 'This order is already paid.' : 'Order not found.', $payment?->status === 'paid');
        }

        return response()->view('pay.checkout', ['options' => [
            'key' => $this->razorpay->keyId(),
            'order_id' => $payment->razorpay_order_id,
            'amount' => (int) round(((float) $payment->amount) * 100),
            'currency' => 'INR',
            'name' => 'Meddata',
            'description' => 'Meddata Pro',
            'prefill' => ['email' => (string) User::whereKey($payment->user_id)->value('email')],
            'theme' => ['color' => '#0E4D4A'],
            'redirect' => true,
            'callback_url' => url('/api/v1/pay/complete'),
        ]]);
    }

    /** POST /pay/complete — Razorpay redirect-mode callback. */
    public function complete(Request $request): Response
    {
        $orderId = (string) $request->input('razorpay_order_id', '');
        $paymentId = (string) $request->input('razorpay_payment_id', '');
        $signature = (string) $request->input('razorpay_signature', '');

        if ($paymentId === '') {
            $error = $request->input('error');
            $reason = is_array($error) && ! empty($error['description'])
                ? (string) $error['description'] : 'Payment was not completed.';
            Log::info('Browser checkout returned failure', ['error' => $error]);

            return $this->result(false, $reason);
        }

        $payment = Payment::where('razorpay_order_id', $orderId)->orderByDesc('id')->first();
        if (! $payment || ! $this->razorpay->verifySignature($orderId, $paymentId, $signature)) {
            Log::warning('Browser checkout signature mismatch', ['order_id' => $orderId, 'payment_id' => $paymentId]);
            if ($payment) {
                $this->orders->markFailed($payment, $paymentId);
            }

            return $this->result(false, 'We could not verify this payment. If money was deducted, contact support.');
        }

        $ent = $this->orders->markPaid($payment, $paymentId);
        if (! $ent) {
            return $this->result(false, 'This plan is no longer available. Please contact support.');
        }

        // A replayed callback for an order paid long ago activates nothing.
        return $ent->isActivePaid()
            ? $this->result(true, 'Payment successful. Premium is active — go back to the Meddata app.')
            : $this->result(false, 'This order was already used. If money was deducted, contact support.');
    }

    private function result(bool $ok, string $message, bool $alreadyPaid = false): Response
    {
        return response()->view('pay.result', ['ok' => $ok || $alreadyPaid, 'message' => $message]);
    }
}
