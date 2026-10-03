<?php

namespace App\Models\Concerns;

use App\Models\Shop;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Shared behaviour for shop-scoped rows that sync to devices: client-made
 * UUID keys, a per-shop `version`, and soft-delete tombstones (so deletes
 * propagate on pull).
 */
trait SyncedRow
{
    use SoftDeletes;

    public function initializeSyncedRow(): void
    {
        $this->incrementing = false;
        $this->keyType = 'string';
        $this->guarded = [];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    /** Columns devices may set; everything else is server-controlled. */
    abstract public static function clientFields(): array;
}
