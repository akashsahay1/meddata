<?php

namespace App\Filament\Resources\Entitlements\Pages;

use App\Filament\Resources\Entitlements\EntitlementResource;
use Filament\Actions\DeleteAction;
use Filament\Resources\Pages\EditRecord;

class EditEntitlement extends EditRecord
{
    protected static string $resource = EntitlementResource::class;

    protected function getHeaderActions(): array
    {
        return [
            DeleteAction::make(),
        ];
    }
}
