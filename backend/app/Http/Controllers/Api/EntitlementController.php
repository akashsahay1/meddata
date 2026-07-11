<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\EntitlementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EntitlementController extends Controller
{
    public function __construct(private readonly EntitlementService $entitlements)
    {
    }

    /**
     * GET /entitlement (auth.token)
     * Return the authenticated user's entitlement. Previously this trusted a
     * client-supplied device_id, which let anyone read any device's status;
     * it is now strictly user-scoped.
     */
    public function show(Request $request): JsonResponse
    {
        $deviceId = $request->query('device_id');
        $ent = $this->entitlements->forUser($request->user(), $deviceId ? (string) $deviceId : null);

        return response()->json($this->entitlements->payload($ent));
    }
}
