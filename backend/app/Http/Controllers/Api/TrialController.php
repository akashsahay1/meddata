<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\EntitlementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TrialController extends Controller
{
    public function __construct(private readonly EntitlementService $entitlements)
    {
    }

    /**
     * POST /device/trial (auth.token)
     * Ensure the authenticated user's one-time free trial. Idempotent: a user
     * only ever gets a single trial, regardless of device or reinstall. This is
     * what closes the trial-farming loophole (previously device_id-scoped and
     * unauthenticated).
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['nullable', 'string', 'max:255'],
        ]);

        $ent = $this->entitlements->ensureTrial($request->user(), $data['device_id'] ?? null);
        $payload = $this->entitlements->payload($ent);

        return response()->json([
            'trial_ends_at' => $payload['trial_ends_at'],
            'days_left' => $payload['days_left'],
            'is_trial_active' => $ent->isTrialActive(),
        ]);
    }
}
