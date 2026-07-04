<?php

namespace App\Filament\Resources\PurchaseLogs\Pages;

use App\Filament\Resources\PurchaseLogs\PurchaseLogResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListPurchaseLogs extends ListRecords
{
    protected static string $resource = PurchaseLogResource::class;

    protected function getHeaderActions(): array
    {
        return [
            CreateAction::make(),
        ];
    }
}
