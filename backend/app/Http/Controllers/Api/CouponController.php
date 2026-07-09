<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Coupon;
use App\Models\Plan;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CouponController extends Controller
{
    /** Validate a coupon against a plan and return the resulting discount. */
    public function validateCode(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string'],
            'plan_id' => ['required', 'integer'],
        ]);

        $plan = Plan::find($data['plan_id']);
        if (! $plan) {
            return response()->json([
                'valid' => false,
                'message' => 'Plan not found.',
            ], 422);
        }

        $amount = (float) $plan->price;

        $coupon = Coupon::where('code', $data['code'])->first();
        if (! $coupon) {
            return response()->json([
                'valid' => false,
                'discount' => 0,
                'final_amount' => $amount,
                'message' => 'Invalid coupon code.',
            ]);
        }

        $check = $coupon->isValidFor((int) $plan->id, $amount);
        if (! $check['ok']) {
            return response()->json([
                'valid' => false,
                'type' => $coupon->type,
                'value' => (float) $coupon->value,
                'discount' => 0,
                'final_amount' => $amount,
                'message' => $check['message'],
            ]);
        }

        $discount = $coupon->discountFor($amount);

        return response()->json([
            'valid' => true,
            'type' => $coupon->type,
            'value' => (float) $coupon->value,
            'discount' => $discount,
            'final_amount' => round($amount - $discount, 2),
            'message' => $check['message'],
        ]);
    }
}
