<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Plan extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'name', 'product_id', 'billing_period', 'price', 'currency',
        'badge', 'is_best_value', 'is_active', 'sort_order', 'features',
    ];

    protected $casts = [
        'price' => 'decimal:2',
        'is_best_value' => 'boolean',
        'is_active' => 'boolean',
        'features' => 'array',
    ];
}
