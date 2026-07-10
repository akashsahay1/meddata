<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Entitlement extends Model
{
    protected $fillable = [
        'device_id', 'user_id', 'plan_id', 'product_id', 'status',
        'purchase_token', 'expiry_time', 'is_premium',
        'trial_started_at', 'trial_ends_at', 'source',
        'razorpay_payment_id', 'razorpay_order_id', 'coupon_id',
    ];

    protected $casts = [
        'expiry_time' => 'datetime',
        'is_premium' => 'boolean',
        'trial_started_at' => 'datetime',
        'trial_ends_at' => 'datetime',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    public function coupon(): BelongsTo
    {
        return $this->belongsTo(Coupon::class);
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

    /** Whether this entitlement is an active PAID subscription (not trial). */
    public function isActivePaid(): bool
    {
        if ($this->status !== 'active') {
            return false;
        }
        if ($this->product_id && str_contains($this->product_id, 'lifetime')) {
            return true;
        }
        if (is_null($this->expiry_time)) {
            // Active with no expiry from a paid source counts as lifetime.
            return in_array($this->source, ['razorpay', 'manual', 'coupon'], true);
        }
        return $this->expiry_time->isFuture();
    }

    /** Whether the free trial window is still open. */
    public function isTrialActive(): bool
    {
        return $this->trial_ends_at && $this->trial_ends_at->isFuture();
    }
}
