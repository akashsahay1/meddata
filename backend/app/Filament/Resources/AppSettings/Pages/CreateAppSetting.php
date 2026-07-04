<?php

namespace App\Filament\Resources\AppSettings\Pages;

use App\Filament\Resources\AppSettings\AppSettingResource;
use Filament\Resources\Pages\CreateRecord;

class CreateAppSetting extends CreateRecord
{
    protected static string $resource = AppSettingResource::class;
}
