<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MedicineMaster extends Model
{
    protected $table = 'medicines_master';

    /** The id is supplied from the source data, not auto-generated. */
    public $incrementing = false;

    public $timestamps = false;

    protected $guarded = [];

    protected $casts = [
        'price' => 'decimal:2',
        'is_discontinued' => 'boolean',
    ];
}
