<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ShopDevice extends Model
{
    protected $fillable = [
        'shop_id', 'user_id', 'device_uuid', 'name', 'platform', 'app_version',
        'last_pull_version', 'last_sync_at',
    ];

    protected function casts(): array
    {
        return ['last_sync_at' => 'datetime'];
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }
}
