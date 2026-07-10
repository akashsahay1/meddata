<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ApiToken extends Model
{
    protected $fillable = [
        'user_id', 'token', 'name', 'last_used_at',
    ];

    protected $casts = [
        'last_used_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** SHA-256 hex hash of a plaintext token; never store the plaintext. */
    public static function hashToken(string $plain): string
    {
        return hash('sha256', $plain);
    }
}
