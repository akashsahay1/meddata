<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppSetting;
use App\Models\Plan;
use Illuminate\Http\JsonResponse;

class ConfigController extends Controller
{
    /** Remote app config + plan list for the paywall. */
    public function index(): JsonResponse
    {
        return response()->json([
            'free_tier_limit' => (int) AppSetting::get('free_tier_limit', 7),
            'expiry_warning_days' => (int) AppSetting::get('expiry_warning_days', 30),
            'low_stock_default' => (int) AppSetting::get('low_stock_default', 10),
            'support_email' => AppSetting::get('support_email', 'support@example.com'),
            'support_whatsapp' => $this->whatsappNumber((string) AppSetting::get('support_whatsapp', '')),
            'maintenance' => (bool) AppSetting::get('maintenance_mode', false),
            'trial_days' => (int) AppSetting::get('trial_days', 7),
            'razorpay_key_id' => (string) AppSetting::get('razorpay_key_id', ''),
            'plans' => Plan::where('is_active', true)
                ->orderBy('sort_order')
                ->get()
                ->map(fn (Plan $p) => [
                    'id' => $p->id,
                    'product_id' => $p->product_id,
                    'name' => $p->name,
                    'price' => (float) $p->price,
                    'currency' => $p->currency,
                    'period' => $p->billing_period,
                    'badge' => $p->badge,
                    'is_best_value' => $p->is_best_value,
                    'features' => $p->features ?? [],
                ]),
        ]);
    }

    /**
     * Normalise an admin-entered number to wa.me form: digits only, with a
     * 91 country code assumed for a bare 10-digit Indian mobile.
     */
    private function whatsappNumber(string $raw): string
    {
        $digits = preg_replace('/\D+/', '', $raw) ?? '';
        if (strlen($digits) === 11 && str_starts_with($digits, '0')) {
            $digits = substr($digits, 1);
        }

        return strlen($digits) === 10 ? '91'.$digits : $digits;
    }
}
