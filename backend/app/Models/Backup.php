<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Backup extends Model
{
    protected $fillable = [
        'device_id', 'user_id', 'path', 'size', 'medicine_count',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
