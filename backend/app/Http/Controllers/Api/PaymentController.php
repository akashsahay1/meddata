<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Coupon;
use App\Models\Payment;
use App\Models\Plan;
use App\Services\OrderPaymentService;
use App\Services\RazorpayService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Log;

class PaymentController extends Controller
{
    public function __construct(
        private readonly RazorpayService $razorpay,
        private readonly OrderPaymentService $orders,
    ) {}

    /**
     * POST /order/create (auth.token)
     * Create a Razorpay order for a plan (optionally with a coupon), owned by
     * the authenticated user.
     */
    public function createOrder(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['nullable', 'string', 'max:255'],
            'plan_id' => ['required', 'integer'],
            'coupon_code' => ['nullable', 'string'],
        ]);

        $user = $request->user();

        $plan = Plan::find($data['plan_id']);
        if (! $plan || ! $plan->is_active) {
            return response()->json(['message' => 'Plan not found.'], 422);
        }

        $amount = (float) $plan->price;
        [$coupon, $discount] = $this->resolveCoupon($data['coupon_code'] ?? null, $plan, $amount);
        $finalAmount = round($amount - $discount, 2);
        $amountPaise = (int) round($finalAmount * 100);

        try {
            $order = $this->razorpay->createOrder($amountPaise, 'rcpt_'.$plan->id.'_'.uniqid());
        } catch (\Throwable $e) {
            Log::error('Order create failed for user '.$user->id.': '.$e->getMessage());

            return response()->json(['message' => 'Payment gateway error. Please try again later.'], 502);
        }

        Payment::create([
            'device_id' => $data['device_id'] ?? ('user-'.$user->id),
            'user_id' => $user->id,
            'plan_id' => $plan->id,
            'coupon_id' => $coupon?->id,
            'amount' => $finalAmount,
            'currency' => $order['currency'],
            'razorpay_order_id' => $order['order_id'],
            'status' => 'created',
        ]);

        return response()->json([
            'order_id' => $order['order_id'],
            'amount' => $order['amount'],
            'currency' => $order['currency'],
            'key_id' => $order['key_id'],
            'final_amount_rupees' => $finalAmount,
        ]);
    }

    /**
     * POST /payment/verify (auth.token)
     * Verify a Razorpay payment signature and activate the entitlement.
     *
     * The plan and amount are taken from the ORDER we created (Payment row),
     * never from the client, so a caller cannot pay for a cheap plan and claim
     * an expensive one. The order must belong to the authenticated user.
     */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['nullable', 'string', 'max:255'],
            'razorpay_order_id' => ['required', 'string'],
            'razorpay_payment_id' => ['required', 'string'],
            'razorpay_signature' => ['nullable', 'string'],
        ]);

        $user = $request->user();

        $payment = Payment::where('razorpay_order_id', $data['razorpay_order_id'])
            ->where('user_id', $user->id)
            ->orderByDesc('id')
            ->first();

        // No order, or an order that isn't this user's: refuse.
        if (! $payment) {
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        $ok = $this->razorpay->verifySignature(
            $data['razorpay_order_id'],
            $data['razorpay_payment_id'],
            (string) ($data['razorpay_signature'] ?? ''),
        );

        if (! $ok) {
            Log::warning('Razorpay signature mismatch', [
                'user_id' => $user->id,
                'order_id' => $data['razorpay_order_id'],
                'payment_id' => $data['razorpay_payment_id'],
            ]);
            $this->orders->markFailed($payment, $data['razorpay_payment_id']);

            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        $ent = $this->orders->markPaid($payment, $data['razorpay_payment_id'], $data['device_id'] ?? null);
        if (! $ent) {
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        return response()->json([
            'premium' => true,
            'status' => 'active',
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
        ]);
    }

    /**
     * POST /payment/return (public)
     * Razorpay redirect-mode callback_url. Renders a page that hands the
     * checkout result to the app's `RZP` JavaScript channel. Nothing is
     * trusted here: the app still sends it to /payment/verify.
     */
    public function checkoutReturn(Request $request): Response
    {
        $error = $request->input('error');

        $payload = $request->filled('razorpay_payment_id')
            ? [
                'status' => 'success',
                'razorpay_payment_id' => (string) $request->input('razorpay_payment_id'),
                'razorpay_order_id' => (string) $request->input('razorpay_order_id', ''),
                'razorpay_signature' => (string) $request->input('razorpay_signature', ''),
            ]
            : [
                'status' => 'failed',
                'error' => is_array($error) && ! empty($error['description'])
                    ? (string) $error['description']
                    : 'payment failed',
            ];

        if ($payload['status'] === 'failed') {
            Log::info('Razorpay checkout returned failure', ['error' => $error]);
        }

        return response()->view('payment.return', ['payload' => $payload]);
    }

    /* ---------------- helpers ---------------- */

    /**
     * Look up and validate a coupon for a plan/amount.
     *
     * @return array{0: ?Coupon, 1: float} [coupon, discount]
     */
    private function resolveCoupon(?string $code, Plan $plan, float $amount): array
    {
        if (! $code) {
            return [null, 0.0];
        }

        $coupon = Coupon::where('code', $code)->first();
        if (! $coupon) {
            return [null, 0.0];
        }

        $check = $coupon->isValidFor((int) $plan->id, $amount);
        if (! $check['ok']) {
            return [null, 0.0];
        }

        return [$coupon, $coupon->discountFor($amount)];
    }
}
