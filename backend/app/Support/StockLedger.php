<?php

namespace App\Support;

use App\Models\Batch;
use App\Models\Shop;
use App\Models\StockMovement;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * Server-made stock movements (purchases, returns) and the batch qty they
 * change. Each movement and each recomputed batch gets a new shop version,
 * so devices receive them through the normal sync pull. Callers hold the
 * shop row lock inside a transaction.
 */
final class StockLedger
{
    public static function move(Shop $shop, ?User $user, ?string $deviceId, string $batchId, string $productId,
        int $delta, string $reason, string $refType, string $refId): StockMovement
    {
        $movement = new StockMovement;
        $movement->id = (string) Str::uuid();
        $movement->fill([
            'shop_id' => $shop->id,
            'batch_id' => $batchId,
            'product_id' => $productId,
            'delta_units' => $delta,
            'reason' => $reason,
            'ref_type' => $refType,
            'ref_id' => $refId,
            'occurred_at' => now(),
            'created_by' => $user?->id,
            'device_id' => $deviceId,
        ]);
        $movement->version = $shop->nextVersion();
        $movement->save();

        return $movement;
    }

    /**
     * Recompute each batch's qty from its movements and publish it.
     *
     * @param  array<int, string>  $batchIds
     * @return list<array{batch_id: string, qty_units: int}>
     */
    public static function refresh(Shop $shop, array $batchIds): array
    {
        $out = [];
        foreach (Batch::withTrashed()->whereIn('id', array_values(array_unique($batchIds)))->orderBy('id')->get() as $batch) {
            $batch->qty_units = (int) StockMovement::where('batch_id', $batch->id)->sum('delta_units');
            $batch->version = $shop->nextVersion();
            $batch->save();
            $out[] = ['batch_id' => $batch->id, 'qty_units' => (int) $batch->qty_units];
        }

        return $out;
    }
}
