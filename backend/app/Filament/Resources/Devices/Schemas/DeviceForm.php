<?php

namespace App\Filament\Resources\Devices\Schemas;

use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;

class DeviceForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('device_id')
                    ->required(),
                Select::make('user_id')
                    ->relationship('user', 'name')
                    ->default(null),
                TextInput::make('platform')
                    ->required()
                    ->default('android'),
                TextInput::make('app_version')
                    ->default(null),
                DateTimePicker::make('last_seen_at'),
            ]);
    }
}
