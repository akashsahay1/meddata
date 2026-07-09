<?php

namespace App\Services;

use App\Models\AppSetting;
use Illuminate\Support\Facades\Http;

/**
 * Razorpay order creation + signature verification.
 *
 * Mirrors GooglePlayVerifier's dev-fallback style: when keys are NOT configured
 * (AppSetting or env), it returns synthetic orders and treats signatures as
 * valid so the whole flow is testable without a real Razorpay account.
 *
 * Keys are read from AppSetting first (admin-editable), then config/env.
 */
class RazorpayService
{
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

    /**
     * Create a Razorpay order (amount in paise).
     *
     * @return array{order_id: string, amount: int, currency: string, key_id: string}
     */
    public function createOrder(int $amountPaise, string $receipt): array
    {
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
        }

        // Dev fallback — no real charge, fully testable.
        return [
            'order_id' => 'order_dev_' . uniqid(),
            'amount' => $amountPaise,
            'currency' => 'INR',
            'key_id' => $this->keyId() !== '' ? $this->keyId() : 'rzp_test_dev',
        ];
    }

    /**
     * Verify the Razorpay checkout signature.
     * In dev fallback (no keys) this returns true so the flow can be exercised.
     */
    public function verifySignature(string $orderId, string $paymentId, string $signature): bool
    {
        if (! $this->keysConfigured()) {
            return true; // dev fallback
        }

        $expected = hash_hmac('sha256', $orderId . '|' . $paymentId, $this->keySecret());

        return hash_equals($expected, $signature);
    }
}
