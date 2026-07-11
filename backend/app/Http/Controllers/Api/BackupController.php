<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Backup;
use App\Models\User;
use App\Services\EntitlementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class BackupController extends Controller
{
    /**
     * Max encoded blob size, kept comfortably under PHP's post_max_size (2 MB
     * here) so oversized uploads are rejected cleanly by validation instead of
     * being silently dropped by PHP. 1.5 MB of base64 is ample for a medicine
     * list backup.
     */
    private const MAX_BLOB_CHARS = 1_500_000;

    public function __construct(private readonly EntitlementService $entitlements)
    {
    }

    /**
     * POST /backup (auth.token, premium only)
     * Upload an encrypted backup blob for the authenticated user. Previously
     * this authorized on a client-supplied device_id, so anyone could read or
     * overwrite another device's backup; it is now strictly user-scoped.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['nullable', 'string', 'max:255'],
            'blob' => ['required', 'string', 'max:' . self::MAX_BLOB_CHARS],
            'medicine_count' => ['nullable', 'integer', 'min:0'],
        ]);

        $user = $request->user();

        if (! $this->isPremium($user)) {
            return response()->json(['error' => 'premium_required'], 403);
        }

        $path = "backups/user-{$user->id}/latest.bin";
        Storage::put($path, base64_decode($data['blob'], true) ?: $data['blob']);

        $backup = Backup::updateOrCreate(
            ['user_id' => $user->id],
            [
                'device_id' => $data['device_id'] ?? ('user-' . $user->id),
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

    /**
     * GET /backup/latest (auth.token, premium only)
     * Fetch the latest backup blob for the authenticated user.
     */
    public function latest(Request $request): JsonResponse
    {
        $user = $request->user();

        if (! $this->isPremium($user)) {
            return response()->json(['error' => 'premium_required'], 403);
        }

        $backup = Backup::where('user_id', $user->id)->latest('id')->first();
        if (! $backup || ! Storage::exists($backup->path)) {
            return response()->json(['error' => 'not_found'], 404);
        }

        return response()->json([
            'blob' => base64_encode(Storage::get($backup->path)),
            'medicine_count' => $backup->medicine_count,
            'updated_at' => $backup->updated_at?->toIso8601String(),
        ]);
    }

    private function isPremium(User $user): bool
    {
        $ent = $this->entitlements->forUser($user);
        $ent->refreshStatus();

        return $ent->isActivePaid() || $ent->isTrialActive();
    }
}
