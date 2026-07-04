<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Medicine extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'store_id', 'name', 'brand', 'category', 'batch_no',
        'barcode', 'quantity', 'unit', 'expiry_date', 'selling_price',
    ];

    protected $casts = [
        'quantity' => 'integer',
        'expiry_date' => 'date',
        'selling_price' => 'decimal:2',
    ];

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }
}
