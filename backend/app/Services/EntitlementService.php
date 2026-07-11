<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\Entitlement;
use App\Models\User;

/**
 * Single source of truth for a user's entitlement.
 *
 * Entitlements are now USER-scoped: exactly one row per user. `device_id` is
 * retained only as informational metadata (the last device seen) and is NEVER
 * used as an authorization key - that was the root cause of the trial-farming
 * and IDOR issues (a client-chosen device string could mint trials and read
 * other users' data). All API callers resolve the entitlement from the
 * authenticated user via this service.
 */
class EntitlementService
{
    /**
     * The user's single entitlement row, creating an empty one if none exists.
     * When a device_id is supplied it is recorded on the row for reference only.
     */
    public function forUser(User $user, ?string $deviceId = null): Entitlement
    {
        $ent = Entitlement::where('user_id', $user->id)->orderByDesc('id')->first();

        if (! $ent) {
            $ent = new Entitlement([
                'device_id' => $deviceId ?: ('user-' . $user->id),
                'user_id' => $user->id,
            ]);
            $ent->save();
        } elseif ($deviceId && $ent->device_id !== $deviceId) {
            // Track the latest device without ever creating a second row.
            $ent->device_id = $deviceId;
            $ent->save();
        }

        return $ent;
    }

    /**
     * Start the free trial exactly ONCE per user, ever. No-op if the user has
     * already consumed a trial or currently holds an active paid subscription.
     * This is what closes the trial-farming loophole: reinstalling, switching
     * devices, or hitting the endpoint directly cannot grant a second trial.
     */
    public function ensureTrial(User $user, ?string $deviceId = null): Entitlement
    {
        $ent = $this->forUser($user, $deviceId);

        $hasHadTrial = Entitlement::where('user_id', $user->id)
            ->whereNotNull('trial_started_at')
            ->exists();

        if (! $hasHadTrial && is_null($ent->trial_started_at) && ! $ent->isActivePaid()) {
            $days = (int) AppSetting::get('trial_days', 7);
            $ent->trial_started_at = now();
            $ent->trial_ends_at = now()->addDays($days);
            $ent->source = $ent->source ?: 'trial';
            $ent->save();
        }

        return $ent;
    }

    /**
     * Serialize an entitlement into the app's standard payload shape.
     * Keeps a single canonical representation used by every endpoint.
     */
    public function payload(?Entitlement $ent): array
    {
        if (! $ent) {
            return [
                'premium' => false,
                'status' => 'expired',
                'source' => null,
                'trial_ends_at' => null,
                'days_left' => 0,
                'expiry_time' => null,
                'product_id' => null,
            ];
        }

        $ent->refreshStatus();
        $ent->save();

        $paidActive = $ent->isActivePaid();
        $trialActive = $ent->isTrialActive();
        $premium = $paidActive || $trialActive;

        $daysLeft = 0;
        if ($paidActive && $ent->expiry_time) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->expiry_time, false));
        } elseif ($trialActive) {
            $daysLeft = (int) ceil(now()->diffInDays($ent->trial_ends_at, false));
        }

        return [
            'premium' => $premium,
            'status' => $premium ? 'active' : 'expired',
            'source' => $paidActive ? ($ent->source ?: 'razorpay') : ($trialActive ? 'trial' : $ent->source),
            'trial_ends_at' => optional($ent->trial_ends_at)->toIso8601String(),
            'days_left' => max(0, $daysLeft),
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
            'product_id' => $ent->product_id,
        ];
    }
}
