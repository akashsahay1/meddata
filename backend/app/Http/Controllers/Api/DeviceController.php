<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DeviceController extends Controller
{
    /** Register / touch an anonymous device (no login required). */
    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
            'platform' => ['nullable', 'string'],
            'app_version' => ['nullable', 'string'],
        ]);

        $device = Device::updateOrCreate(
            ['device_id' => $data['device_id']],
            [
                'platform' => $data['platform'] ?? 'android',
                'app_version' => $data['app_version'] ?? null,
                'last_seen_at' => now(),
            ],
        );

        return response()->json(['ok' => true, 'device_id' => $device->device_id]);
    }
}
