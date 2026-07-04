<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Entitlement extends Model
{
    protected $fillable = [
        'device_id', 'plan_id', 'product_id', 'status',
        'purchase_token', 'expiry_time', 'is_premium',
    ];

    protected $casts = [
        'expiry_time' => 'datetime',
        'is_premium' => 'boolean',
    ];

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    /** Recompute premium/status from the expiry date. */
    public function refreshStatus(): void
    {
        if ($this->product_id && str_contains($this->product_id, 'lifetime')) {
            $this->status = 'active';
            $this->is_premium = true;
            return;
        }
        if ($this->expiry_time && $this->expiry_time->isFuture()) {
            $this->status = 'active';
            $this->is_premium = true;
        } else {
            $this->status = 'expired';
            $this->is_premium = false;
        }
    }
}
