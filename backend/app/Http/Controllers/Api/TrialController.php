<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppSetting;
use App\Models\Entitlement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class TrialController extends Controller
{
    /**
     * Register (or return) the 7-day free trial for a device. Idempotent:
     * the first call sets the trial window; later calls just report it.
     */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
        ]);

        $trialDays = (int) AppSetting::get('trial_days', 7);

        $ent = Entitlement::firstOrNew(['device_id' => $data['device_id']]);

        // Only start a trial if one hasn't started and there's no active paid sub.
        if (is_null($ent->trial_started_at) && ! $ent->isActivePaid()) {
            $ent->trial_started_at = now();
            $ent->trial_ends_at = now()->addDays($trialDays);
            if (is_null($ent->source)) {
                $ent->source = 'trial';
            }
            $ent->save();
        } elseif (! $ent->exists) {
            $ent->save();
        }

        $isActive = $ent->isTrialActive();
        $daysLeft = $isActive
            ? (int) ceil(now()->diffInDays($ent->trial_ends_at, false))
            : 0;

        return response()->json([
            'trial_ends_at' => optional($ent->trial_ends_at)->toIso8601String(),
            'days_left' => $daysLeft,
            'is_trial_active' => $isActive,
        ]);
    }
}
