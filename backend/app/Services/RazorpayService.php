<?php

namespace App\Services;

use App\Models\AppSetting;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

/**
 * Razorpay order creation + signature verification.
 *
 * Keys are read from AppSetting first (admin-editable), then config/env.
 *
 * Without keys nothing can be charged or verified. Only the local and testing
 * environments then fall back to synthetic orders and accept any signature, so
 * the flow can be exercised without a Razorpay account. Every other environment
 * fails closed: no order is created and no payment verifies, so a blank key in
 * the admin panel can never hand out a subscription.
 */
class RazorpayService
{
    /** Key id the dev fallback hands the app in place of a real one. */
    public const DEV_KEY_ID = 'rzp_test_dev';

    public function keyId(): string
    {
        return (string) (AppSetting::get('razorpay_key_id', '') ?: config('services.razorpay.key_id', ''));
    }

    public function keySecret(): string
    {
        return (string) (AppSetting::get('razorpay_key_secret', '') ?: config('services.razorpay.key_secret', ''));
    }

    /** Both key id and secret are present. */
    public function keysConfigured(): bool
    {
        return $this->keyId() !== '' && $this->keySecret() !== '';
    }

    /** Synthetic orders and unchecked signatures: local dev and tests only. */
    public function devFallbackAllowed(): bool
    {
        return app()->environment('local', 'testing');
    }

    /** Whether orders can be taken at all: real keys, or the dev fallback. */
    public function paymentsAvailable(): bool
    {
        return $this->keysConfigured() || $this->devFallbackAllowed();
    }

    /**
     * Create a Razorpay order (amount in paise).
     *
     * @return array{order_id: string, amount: int, currency: string, key_id: string}
     */
    public function createOrder(int $amountPaise, string $receipt): array
    {
        // A key id without a secret can't create real orders, and handing a
        // synthetic order to the real checkout makes it fail silently.
        if ($this->keyId() !== '' && $this->keySecret() === '') {
            Log::error('Razorpay key_id is set but key_secret is missing; cannot create order.');
            throw new RuntimeException('Razorpay key secret is not configured.');
        }

        if ($this->keysConfigured()) {
            $response = Http::withBasicAuth($this->keyId(), $this->keySecret())
                ->acceptJson()
                ->post('https://api.razorpay.com/v1/orders', [
                    'amount' => $amountPaise,
                    'currency' => 'INR',
                    'receipt' => $receipt,
                ]);

            if ($response->successful()) {
                $data = $response->json();
                return [
                    'order_id' => $data['id'] ?? ('order_' . uniqid()),
                    'amount' => (int) ($data['amount'] ?? $amountPaise),
                    'currency' => $data['currency'] ?? 'INR',
                    'key_id' => $this->keyId(),
                ];
            }

            // Real keys but Razorpay rejected the call (bad secret, test/live
            // mismatch, amount < 100 paise, ...). Never fall back to a fake
            // order here: checkout.js would reject it with no visible error.
            Log::error('Razorpay order creation failed', [
                'status' => $response->status(),
                'body' => $response->json() ?? $response->body(),
                'amount_paise' => $amountPaise,
            ]);
            throw new RuntimeException('Razorpay order creation failed: ' . ($response->json('error.description') ?? $response->status()));
        }

        // No keys outside local/testing: refuse rather than hand out a fake order.
        if (! $this->devFallbackAllowed()) {
            Log::error('Razorpay keys are not configured; refusing to create an order.');
            throw new RuntimeException('Razorpay keys are not configured.');
        }

        // Dev fallback — no real charge, fully testable.
        return [
            'order_id' => 'order_dev_' . uniqid(),
            'amount' => $amountPaise,
            'currency' => 'INR',
            'key_id' => self::DEV_KEY_ID,
        ];
    }

    /**
     * Verify the Razorpay checkout signature. Without keys only the dev
     * fallback (local/testing) accepts it; every other environment rejects it.
     */
    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        if (! $this->keysConfigured()) {
            // Fail CLOSED: without keys we cannot verify a real payment, so
            // never grant premium. Only local/testing may bypass so the flow
            // stays exercisable without a Razorpay account. (Checking for
            // 'production' alone left staging or a mistyped APP_ENV open.)
            return $this->devFallbackAllowed();
        }

        $expected = hash_hmac('sha256', $orderId . '|' . $paymentId, $this->keySecret());

        return hash_equals($expected, $signature);
    }
}
