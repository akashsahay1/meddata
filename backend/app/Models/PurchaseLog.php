<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PurchaseLog extends Model
{
    protected $fillable = [
        'device_id', 'product_id', 'purchase_token', 'event', 'result', 'payload',
    ];

    protected $casts = [
        'payload' => 'array',
    ];
}
