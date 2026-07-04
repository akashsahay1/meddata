<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Entitlement;
use App\Models\Plan;
use App\Models\PurchaseLog;
use App\Services\GooglePlayVerifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PurchaseController extends Controller
{
    public function __construct(private readonly GooglePlayVerifier $verifier)
    {
    }

    /** Verify a Google Play purchase token and store the entitlement. */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
            'product_id' => ['required', 'string'],
            'purchase_token' => ['required', 'string'],
        ]);

        $result = $this->verifier->verify($data['product_id'], $data['purchase_token']);

        PurchaseLog::create([
            'device_id' => $data['device_id'],
            'product_id' => $data['product_id'],
            'purchase_token' => $data['purchase_token'],
            'event' => 'verify',
            'result' => $result['valid'] ? $result['status'] : 'invalid',
            'payload' => $result,
        ]);

        if (! $result['valid']) {
            return response()->json(['premium' => false, 'status' => 'invalid'], 422);
        }

        $plan = Plan::where('product_id', $data['product_id'])->first();

        $ent = Entitlement::updateOrCreate(
            ['device_id' => $data['device_id']],
            [
                'plan_id' => $plan?->id,
                'product_id' => $data['product_id'],
                'purchase_token' => $data['purchase_token'],
                'expiry_time' => $result['expiry'],
            ],
        );
        $ent->refreshStatus();
        $ent->save();

        return response()->json([
            'premium' => $ent->is_premium,
            'status' => $ent->status,
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
        ]);
    }

    /** Google Play Real-Time Developer Notifications (Pub/Sub push) webhook. */
    public function rtdn(Request $request): JsonResponse
    {
        $payload = $request->all();
        PurchaseLog::create([
            'device_id' => 'rtdn',
            'event' => 'rtdn',
            'result' => 'received',
            'payload' => $payload,
        ]);

        // Decode Pub/Sub message → subscriptionNotification → re-verify token →
        // update the matching entitlement's status/expiry. Structure in place;
        // wire to GooglePlayVerifier when service-account creds are configured.

        return response()->json(['ok' => true]);
    }
}
