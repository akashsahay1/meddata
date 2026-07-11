<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Entitlements are now user-scoped (one row per user). Historically `device_id`
 * was only indexed, so a user could accumulate several rows (e.g. a device-trial
 * row plus a login row). This migration:
 *   1. Merges duplicate rows per user into a single keeper (preserving the
 *      earliest trial start, the latest trial end, and any paid subscription).
 *   2. Adds a UNIQUE index on user_id so duplicates can never recur.
 *
 * Rows with a NULL user_id (legacy anonymous device entitlements) are left
 * untouched; MySQL permits multiple NULLs under a unique index.
 */
return new class extends Migration
{
    public function up(): void
    {
        $userIds = DB::table('entitlements')
            ->whereNotNull('user_id')
            ->select('user_id')
            ->groupBy('user_id')
            ->havingRaw('COUNT(*) > 1')
            ->pluck('user_id');

        foreach ($userIds as $userId) {
            $rows = DB::table('entitlements')
                ->where('user_id', $userId)
                ->orderBy('id')
                ->get();

            // Prefer a paid row as the keeper; otherwise keep the newest row.
            $paid = $rows->firstWhere('expiry_time', '!=', null);
            $keeper = $paid ?: $rows->last();

            // Consolidate the trial window across all of the user's rows.
            $trialStarts = $rows->pluck('trial_started_at')->filter()->sort()->values();
            $trialEnds = $rows->pluck('trial_ends_at')->filter()->sort()->values();

            DB::table('entitlements')->where('id', $keeper->id)->update([
                'trial_started_at' => $trialStarts->first() ?: $keeper->trial_started_at,
                'trial_ends_at' => $trialEnds->last() ?: $keeper->trial_ends_at,
                'source' => $keeper->source ?: ($rows->pluck('source')->filter()->first()),
                'updated_at' => now(),
            ]);

            DB::table('entitlements')
                ->where('user_id', $userId)
                ->where('id', '!=', $keeper->id)
                ->delete();
        }

        Schema::table('entitlements', function (Blueprint $table) {
            $table->unique('user_id');
        });
    }

    public function down(): void
    {
        Schema::table('entitlements', function (Blueprint $table) {
            $table->dropUnique(['user_id']);
        });
    }
};
