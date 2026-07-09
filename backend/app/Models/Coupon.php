<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Coupon extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'code', 'type', 'value', 'max_uses', 'used_count',
        'min_amount', 'plan_id', 'valid_from', 'valid_until', 'is_active',
    ];

    protected $casts = [
        'value' => 'decimal:2',
        'min_amount' => 'decimal:2',
        'max_uses' => 'integer',
        'used_count' => 'integer',
        'valid_from' => 'datetime',
        'valid_until' => 'datetime',
        'is_active' => 'boolean',
    ];

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    /** Discount amount for a given order total (never exceeds the total). */
    public function discountFor(float $amount): float
    {
        $discount = $this->type === 'percentage'
            ? $amount * ((float) $this->value / 100)
            : (float) $this->value;

        $discount = max(0.0, $discount);

        return round(min($discount, $amount), 2);
    }

    /**
     * Whether this coupon may be applied to the given plan/amount.
     *
     * @return array{ok: bool, message: string}
     */
    public function isValidFor(?int $planId, float $amount): array
    {
        if (! $this->is_active) {
            return ['ok' => false, 'message' => 'This coupon is not active.'];
        }

        $now = now();
        if ($this->valid_from && $now->lt($this->valid_from)) {
            return ['ok' => false, 'message' => 'This coupon is not valid yet.'];
        }
        if ($this->valid_until && $now->gt($this->valid_until)) {
            return ['ok' => false, 'message' => 'This coupon has expired.'];
        }

        if (! is_null($this->max_uses) && $this->used_count >= $this->max_uses) {
            return ['ok' => false, 'message' => 'This coupon has reached its usage limit.'];
        }

        if (! is_null($this->min_amount) && $amount < (float) $this->min_amount) {
            return ['ok' => false, 'message' => 'Order amount is below the minimum for this coupon.'];
        }

        if (! is_null($this->plan_id) && $this->plan_id !== $planId) {
            return ['ok' => false, 'message' => 'This coupon does not apply to the selected plan.'];
        }

        return ['ok' => true, 'message' => 'Coupon applied.'];
    }
}
