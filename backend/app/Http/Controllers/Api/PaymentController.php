<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Coupon;
use App\Models\Entitlement;
use App\Models\Payment;
use App\Models\Plan;
use App\Services\RazorpayService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PaymentController extends Controller
{
    public function __construct(private readonly RazorpayService $razorpay)
    {
    }

    /**
     * Create a Razorpay order for a plan (optionally with a coupon).
     * Returns the order id + amount in paise for the app's checkout.
     */
    public function createOrder(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
            'plan_id' => ['required', 'integer'],
            'coupon_code' => ['nullable', 'string'],
        ]);

        $plan = Plan::find($data['plan_id']);
        if (! $plan) {
            return response()->json(['message' => 'Plan not found.'], 422);
        }

        $amount = (float) $plan->price;
        [$coupon, $discount] = $this->resolveCoupon($data['coupon_code'] ?? null, $plan, $amount);
        $finalAmount = round($amount - $discount, 2);
        $amountPaise = (int) round($finalAmount * 100);

        $order = $this->razorpay->createOrder($amountPaise, 'rcpt_' . $plan->id . '_' . uniqid());

        Payment::create([
            'device_id' => $data['device_id'],
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
     * Verify a Razorpay payment signature and activate the entitlement.
     */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
            'razorpay_order_id' => ['required', 'string'],
            'razorpay_payment_id' => ['required', 'string'],
            'razorpay_signature' => ['nullable', 'string'],
            'plan_id' => ['required', 'integer'],
            'coupon_code' => ['nullable', 'string'],
        ]);

        $ok = $this->razorpay->verifySignature(
            $data['razorpay_order_id'],
            $data['razorpay_payment_id'],
            (string) ($data['razorpay_signature'] ?? ''),
        );

        $payment = Payment::where('razorpay_order_id', $data['razorpay_order_id'])
            ->orderByDesc('id')
            ->first();

        if (! $ok) {
            if ($payment) {
                $payment->update([
                    'status' => 'failed',
                    'razorpay_payment_id' => $data['razorpay_payment_id'],
                ]);
            }
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        $plan = Plan::find($data['plan_id']);
        if (! $plan) {
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        // Resolve coupon (for used_count + linking) using the plan's list price.
        [$coupon] = $this->resolveCoupon($data['coupon_code'] ?? null, $plan, (float) $plan->price);

        if ($payment) {
            $payment->update([
                'status' => 'paid',
                'razorpay_payment_id' => $data['razorpay_payment_id'],
                'coupon_id' => $coupon?->id ?? $payment->coupon_id,
            ]);
        }

        if ($coupon) {
            $coupon->increment('used_count');
        }

        $expiry = $this->expiryForPlan($plan);

        $ent = Entitlement::firstOrNew(['device_id' => $data['device_id']]);
        $ent->fill([
            'plan_id' => $plan->id,
            'product_id' => $plan->product_id,
            'source' => 'razorpay',
            'is_premium' => true,
            'status' => 'active',
            'expiry_time' => $expiry,
            'razorpay_payment_id' => $data['razorpay_payment_id'],
            'razorpay_order_id' => $data['razorpay_order_id'],
            'coupon_id' => $coupon?->id,
        ]);
        $ent->save();

        return response()->json([
            'premium' => true,
            'status' => 'active',
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
        ]);
    }

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

    /** Compute the subscription expiry for a plan's billing period. */
    private function expiryForPlan(Plan $plan): ?\Illuminate\Support\Carbon
    {
        return match ($plan->billing_period) {
            'lifetime' => null,
            'yearly' => now()->addYear(),
            'monthly' => now()->addMonth(),
            default => now()->addMonth(),
        };
    }
}
