<?php

namespace App\Filament\Resources\Backups\Pages;

use App\Filament\Resources\Backups\BackupResource;
use Filament\Actions\DeleteAction;
use Filament\Resources\Pages\EditRecord;

class EditBackup extends EditRecord
{
    protected static string $resource = BackupResource::class;

    protected function getHeaderActions(): array
    {
        return [
            DeleteAction::make(),
        ];
    }
}
