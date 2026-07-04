<?php

namespace App\Filament\Resources\PurchaseLogs\Pages;

use App\Filament\Resources\PurchaseLogs\PurchaseLogResource;
use Filament\Actions\DeleteAction;
use Filament\Resources\Pages\EditRecord;

class EditPurchaseLog extends EditRecord
{
    protected static string $resource = PurchaseLogResource::class;

    protected function getHeaderActions(): array
    {
        return [
            DeleteAction::make(),
        ];
    }
}
