<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Mail\AdminNewPaymentMail;
use App\Mail\PaymentReceiptMail;
use App\Models\AppSetting;
use App\Models\Coupon;
use App\Models\Payment;
use App\Models\Plan;
use App\Services\EntitlementService;
use App\Services\RazorpayService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

class PaymentController extends Controller
{
    public function __construct(
        private readonly RazorpayService $razorpay,
        private readonly EntitlementService $entitlements,
    ) {
    }

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
            $order = $this->razorpay->createOrder($amountPaise, 'rcpt_' . $plan->id . '_' . uniqid());
        } catch (\Throwable $e) {
            Log::error('Order create failed for user ' . $user->id . ': ' . $e->getMessage());
            return response()->json(['message' => 'Payment gateway error. Please try again later.'], 502);
        }

        Payment::create([
            'device_id' => $data['device_id'] ?? ('user-' . $user->id),
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
            $payment->update([
                'status' => 'failed',
                'razorpay_payment_id' => $data['razorpay_payment_id'],
            ]);
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        // Idempotency: if this order was already paid, don't double-apply.
        $alreadyPaid = $payment->status === 'paid';

        $plan = Plan::find($payment->plan_id);
        if (! $plan) {
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        $payment->update([
            'status' => 'paid',
            'razorpay_payment_id' => $data['razorpay_payment_id'],
        ]);

        // Count a coupon use exactly once, atomically, respecting max_uses.
        if (! $alreadyPaid && $payment->coupon_id) {
            $this->consumeCoupon($payment->coupon_id);
        }

        $expiry = $this->expiryForPlan($plan);

        // User-scoped entitlement (was device_id-keyed before).
        $ent = $this->entitlements->forUser($user, $data['device_id'] ?? null);
        $wasPaid = $ent->isActivePaid();

        $ent->fill([
            'plan_id' => $plan->id,
            'product_id' => $plan->product_id,
            'source' => 'razorpay',
            'is_premium' => true,
            'status' => 'active',
            'expiry_time' => $expiry,
            'razorpay_payment_id' => $data['razorpay_payment_id'],
            'razorpay_order_id' => $data['razorpay_order_id'],
            'coupon_id' => $payment->coupon_id,
        ]);
        $ent->save();

        if (! $alreadyPaid) {
            $this->sendReceiptEmails($user, $plan, (float) $payment->amount, $payment->currency,
                $data['razorpay_payment_id'], optional($expiry)->toIso8601String(), $wasPaid);
        }

        return response()->json([
            'premium' => true,
            'status' => 'active',
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
        ]);
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

    /**
     * Atomically increment a coupon's usage without exceeding max_uses.
     * Returns true if the use was counted.
     */
    private function consumeCoupon(int $couponId): bool
    {
        return DB::transaction(function () use ($couponId) {
            $coupon = Coupon::whereKey($couponId)->lockForUpdate()->first();
            if (! $coupon) {
                return false;
            }
            if (! is_null($coupon->max_uses) && $coupon->used_count >= $coupon->max_uses) {
                return false;
            }
            $coupon->increment('used_count');
            return true;
        });
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

    /** Email the customer a receipt and notify the admin (best-effort). */
    private function sendReceiptEmails(
        \App\Models\User $user,
        Plan $plan,
        float $amount,
        string $currency,
        string $paymentId,
        ?string $expiry,
        bool $isRenewal,
    ): void {
        $this->safeMail(fn () => Mail::to($user->email)->send(
            new PaymentReceiptMail($user, $plan->name, $amount, $currency, $paymentId, $expiry, $isRenewal)
        ));

        $admin = AppSetting::get('support_email');
        if ($admin) {
            $this->safeMail(fn () => Mail::to($admin)->send(
                new AdminNewPaymentMail($user, $plan->name, $amount, $currency, $paymentId, $isRenewal)
            ));
        }
    }

    private function safeMail(callable $fn): void
    {
        try {
            $fn();
        } catch (\Throwable $e) {
            Log::warning('Mail send failed: ' . $e->getMessage());
        }
    }
}
