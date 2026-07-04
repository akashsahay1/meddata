<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
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
            return response()->json(['premium' => false, 'status' => 'expired']);
        }

        // Re-evaluate against the clock (covers expiry since last write).
        $ent->refreshStatus();
        $ent->save();

        return response()->json([
            'premium' => $ent->is_premium,
            'status' => $ent->status,
            'product_id' => $ent->product_id,
            'expiry_time' => optional($ent->expiry_time)->toIso8601String(),
        ]);
    }
}
