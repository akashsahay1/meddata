<?php

namespace App\Services;

use App\Models\Shop;
use App\Models\ShopDevice;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class ShopService
{
    /**
     * The user's shop, created on first use (one owner login per shop for
     * now, so every app user owns exactly one shop).
     */
    public function forUser(User $user): Shop
    {
        $shop = Shop::query()
            ->whereIn('id', DB::table('shop_users')->where('user_id', $user->id)->select('shop_id'))
            ->orderBy('id')
            ->first();
        if ($shop) {
            return $shop;
        }

        return DB::transaction(function () use ($user) {
            $shop = Shop::create([
                'owner_user_id' => $user->id,
                'name' => $user->name ?: 'My Shop',
                'phone' => $user->phone,
            ]);
            DB::table('shop_users')->insert([
                'shop_id' => $shop->id,
                'user_id' => $user->id,
                'role' => 'owner',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            return $shop;
        });
    }

    /** Register or refresh a device of this shop. */
    public function touchDevice(Shop $shop, User $user, string $deviceUuid, array $info = []): ShopDevice
    {
        $device = ShopDevice::firstOrNew(['shop_id' => $shop->id, 'device_uuid' => $deviceUuid]);
        $device->fill(array_filter([
            'user_id' => $user->id,
            'name' => $info['name'] ?? null,
            'platform' => $info['platform'] ?? null,
            'app_version' => $info['app_version'] ?? null,
        ], fn ($v) => $v !== null));
        $device->last_sync_at = now();
        $device->save();

        return $device;
    }
}
