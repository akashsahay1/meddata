<?php

namespace App\Filament\Resources\PurchaseLogs\Pages;

use App\Filament\Resources\PurchaseLogs\PurchaseLogResource;
use Filament\Resources\Pages\CreateRecord;

class CreatePurchaseLog extends CreateRecord
{
    protected static string $resource = PurchaseLogResource::class;
}
