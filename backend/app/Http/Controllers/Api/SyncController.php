<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Shop;
use App\Services\ShopService;
use App\Services\SyncService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SyncController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly SyncService $sync,
    ) {}

    /**
     * GET /sync/status
     * Cheap "has anything changed?" check: devices compare server_version
     * with their cursor and only pull when it moved.
     */
    public function status(Request $request): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());

        return response()->json(['server_version' => (int) Shop::whereKey($shop->id)->value('seq')]);
    }

    /**
     * GET /sync/pull?since=&limit=&device_id=
     * Changed rows (incl. tombstones) after the cursor, oldest first.
     */
    public function pull(Request $request): JsonResponse
    {
        $data = $request->validate([
            'since' => ['nullable', 'integer', 'min:0'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
            'device_id' => ['nullable', 'string', 'max:64'],
        ]);
        $shop = $this->shops->forUser($request->user());

        $result = $this->sync->pull($shop, (int) ($data['since'] ?? 0), (int) ($data['limit'] ?? 500));

        if (! empty($data['device_id'])) {
            $device = $this->shops->touchDevice($shop, $request->user(), $data['device_id']);
            $device->forceFill(['last_pull_version' => $result['next']])->save();
        }

        return response()->json($result);
    }

    /**
     * POST /sync/push
     * {device_id, mutations: [{mutation_id, table, op, id, base_version?, data}]}
     * Returns one result per mutation, in order.
     */
    public function push(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => ['required', 'string', 'max:64'],
            'mutations' => ['required', 'array', 'max:500'],
            'mutations.*' => ['array'],
            'device_name' => ['nullable', 'string', 'max:255'],
            'platform' => ['nullable', 'string', 'max:16'],
            'app_version' => ['nullable', 'string', 'max:32'],
        ]);
        $user = $request->user();
        $shop = $this->shops->forUser($user);
        $this->shops->touchDevice($shop, $user, $data['device_id'], [
            'name' => $data['device_name'] ?? null,
            'platform' => $data['platform'] ?? null,
            'app_version' => $data['app_version'] ?? null,
        ]);

        $results = $this->sync->push($shop, $user, $data['device_id'], $data['mutations']);

        return response()->json([
            'results' => $results,
            'server_version' => (int) Shop::whereKey($shop->id)->value('seq'),
        ]);
    }
}
