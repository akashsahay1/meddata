<?php

namespace App\Services;

use App\Mail\AdminNewPaymentMail;
use App\Mail\PaymentReceiptMail;
use App\Models\AppSetting;
use App\Models\Coupon;
use App\Models\Entitlement;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * Turns a verified Razorpay payment into an active subscription. Shared by
 * the in-app checkout (POST /payment/verify) and the browser checkout used
 * by the desktop app (/pay/...), so both apply the same rules.
 */
class OrderPaymentService
{
    public function __construct(private readonly EntitlementService $entitlements) {}

    /**
     * Mark the order paid and activate the owner's entitlement. An order
     * activates exactly once: calling this again for a paid order (a retried
     * or replayed verify/callback) returns the current entitlement without
     * extending it, counting the coupon or emailing again.
     * Returns null if the order's plan no longer exists.
     */
    public function markPaid(Payment $payment, string $razorpayPaymentId, ?string $deviceId = null): ?Entitlement
    {
        $user = User::find($payment->user_id);
        $plan = Plan::find($payment->plan_id);
        if (! $user || ! $plan) {
            return null;
        }

        // The order row is locked so two concurrent callbacks for the same
        // order can't both activate it.
        $activated = DB::transaction(function () use ($payment, $razorpayPaymentId, $deviceId, $user, $plan) {
            $order = Payment::whereKey($payment->id)->lockForUpdate()->first();
            if (! $order || $order->status === 'paid') {
                return null;
            }
            $order->update(['status' => 'paid', 'razorpay_payment_id' => $razorpayPaymentId]);

            // Count a coupon use exactly once, atomically, respecting max_uses.
            if ($order->coupon_id) {
                $this->consumeCoupon($order->coupon_id);
            }

            $ent = $this->entitlements->forUser($user, $deviceId);
            $wasPaid = $ent->isActivePaid();

            $ent->fill([
                'plan_id' => $plan->id,
                'product_id' => $plan->product_id,
                'source' => 'razorpay',
                'is_premium' => true,
                'status' => 'active',
                'expiry_time' => $this->expiryForPlan($plan),
                'razorpay_payment_id' => $razorpayPaymentId,
                'razorpay_order_id' => $order->razorpay_order_id,
                'coupon_id' => $order->coupon_id,
            ]);
            $ent->save();

            return [$order, $ent, $wasPaid];
        });

        // Paid before: the signature is genuine but already used, so a replay
        // (say, a month later) must not start the plan over again.
        if (! $activated) {
            return $this->entitlements->forUser($user, $deviceId);
        }

        [$order, $ent, $wasPaid] = $activated;
        $this->sendReceiptEmails($user, $plan, (float) $order->amount, $order->currency,
            $razorpayPaymentId, optional($ent->expiry_time)->toIso8601String(), $wasPaid);

        return $ent;
    }

    public function markFailed(Payment $payment, string $razorpayPaymentId): void
    {
        if ($payment->status !== 'paid') {
            $payment->update(['status' => 'failed', 'razorpay_payment_id' => $razorpayPaymentId]);
        }
    }

    /** Atomically increment a coupon's usage without exceeding max_uses. */
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

    /** Subscription expiry for a plan's billing period. */
    private function expiryForPlan(Plan $plan): ?Carbon
    {
        return match ($plan->billing_period) {
            'lifetime' => null,
            'yearly' => now()->addYear(),
            default => now()->addMonth(),
        };
    }

    /** Email the customer a receipt and notify the admin (best-effort). */
    private function sendReceiptEmails(User $user, Plan $plan, float $amount, string $currency,
        string $paymentId, ?string $expiry, bool $isRenewal): void
    {
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
            Log::warning('Mail send failed: '.$e->getMessage());
        }
    }
}
