<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Backup;
use App\Models\Entitlement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class BackupController extends Controller
{
    /** Upload an encrypted backup blob (premium only). */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string'],
            'blob' => ['required', 'string'],          // base64 / encrypted payload
            'medicine_count' => ['nullable', 'integer'],
        ]);

        if (! $this->isPremium($data['device_id'])) {
            return response()->json(['error' => 'premium_required'], 403);
        }

        $path = "backups/{$data['device_id']}/latest.bin";
        Storage::put($path, base64_decode($data['blob']) ?: $data['blob']);

        $backup = Backup::updateOrCreate(
            ['device_id' => $data['device_id']],
            [
                'path' => $path,
                'size' => Storage::size($path),
                'medicine_count' => $data['medicine_count'] ?? 0,
            ],
        );

        return response()->json([
            'ok' => true,
            'size' => $backup->size,
            'updated_at' => $backup->updated_at?->toIso8601String(),
        ]);
    }

    /** Fetch the latest backup blob for a device (premium only). */
    public function latest(Request $request): JsonResponse
    {
        $deviceId = (string) $request->query('device_id', '');
        if (! $this->isPremium($deviceId)) {
            return response()->json(['error' => 'premium_required'], 403);
        }

        $backup = Backup::where('device_id', $deviceId)->latest('id')->first();
        if (! $backup || ! Storage::exists($backup->path)) {
            return response()->json(['error' => 'not_found'], 404);
        }

        return response()->json([
            'blob' => base64_encode(Storage::get($backup->path)),
            'medicine_count' => $backup->medicine_count,
            'updated_at' => $backup->updated_at?->toIso8601String(),
        ]);
    }

    private function isPremium(string $deviceId): bool
    {
        if ($deviceId === '') {
            return false;
        }
        $ent = Entitlement::where('device_id', $deviceId)->latest('id')->first();
        if (! $ent) {
            return false;
        }
        $ent->refreshStatus();
        return $ent->is_premium;
    }
}
