<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ApiToken;
use App\Models\Entitlement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EntitlementController extends Controller
{
    /** Return the current entitlement for a device. */
    public function show(Request $request): JsonResponse
    {
        $deviceId = (string) $request->query('device_id', '');
        if ($deviceId === '') {
            return response()->json(['premium' => false, 'status' => 'expired']);
        }

        $ent = Entitlement::where('device_id', $deviceId)
            ->orderByDesc('id')
            ->first();

        if (! $ent) {
            return response()->json([
                'premium' => false,
                'status' => 'expired',
                'source' => null,
                'trial_ends_at' => null,
                'days_left' => 0,
                'expiry_time' => null,
                'product_id' => null,
            ]);
        }

        // Associate with the authenticated user when a valid Bearer token is present.
        if (($user = $this->tokenUser($request)) && is_null($ent->user_id)) {
            $ent->user_id = $user->id;
        }

        // Re-evaluate the paid subscription against the clock.
        $ent->refreshStatus();
        $ent->save();

        $paidActive = $ent->isActivePaid();
        $trialActive = $ent->isTrialActive();
        $premium = $paidActive || $trialActive;

        // days_left: from paid subscription if active, else from the trial window.
        $daysLeft = 0;
        if ($paidActive && $ent->expiry_time) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->expiry_time, false));
        } elseif ($trialActive) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->trial_ends_at, false));
        }

        $status = $premium ? 'active' : 'expired';
        $source = $paidActive ? ($ent->source ?: 'razorpay') : ($trialActive ? 'trial' : $ent->source);

        return response()->json([
            'premium' => $premium,
            'status' => $status,
            'source' => $source,
            'trial_ends_at' => optional($ent->trial_ends_at)->toIso8601String(),
            'days_left' => max(0, $daysLeft),
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
            'product_id' => $ent->product_id,
            'user_id' => $ent->user_id,
        ]);
    }

    /** Resolve the user from a Bearer token if one is present (optional auth). */
    private function tokenUser(Request $request): ?\App\Models\User
    {
        $plain = $request->bearerToken();
        if (! $plain) {
            return null;
        }

        return ApiToken::where('token', ApiToken::hashToken($plain))->first()?->user;
    }
}
