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
            'maintenance' => (bool) AppSetting::get('maintenance_mode', false),
            'plans' => Plan::where('is_active', true)
                ->orderBy('sort_order')
                ->get()
                ->map(fn (Plan $p) => [
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
}
