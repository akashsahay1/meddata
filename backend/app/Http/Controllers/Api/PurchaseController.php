<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Plan;
use App\Models\PurchaseLog;
use App\Services\EntitlementService;
use App\Services\GooglePlayVerifier;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PurchaseController extends Controller
{
    public function __construct(
        private readonly GooglePlayVerifier $verifier,
        private readonly EntitlementService $entitlements,
    ) {
    }

    /**
     * POST /purchase/verify (auth.token)
     * Verify a Google Play purchase token and store the user's entitlement.
     */
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['nullable', 'string', 'max:255'],
            'product_id' => ['required', 'string'],
            'purchase_token' => ['required', 'string'],
        ]);

        $user = $request->user();

        $result = $this->verifier->verify($data['product_id'], $data['purchase_token']);

        PurchaseLog::create([
            'device_id' => $data['device_id'] ?? ('user-' . $user->id),
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

        $ent = $this->entitlements->forUser($user, $data['device_id'] ?? null);
        $ent->fill([
            'plan_id' => $plan?->id,
            'product_id' => $data['product_id'],
            'purchase_token' => $data['purchase_token'],
            'source' => 'google_play',
            'expiry_time' => $result['expiry'],
        ]);
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

        // Decode Pub/Sub message, re-verify token, update the matching
        // entitlement's status/expiry once service-account creds are configured.

        return response()->json(['ok' => true]);
    }
}
