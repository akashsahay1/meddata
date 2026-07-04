<?php

namespace App\Filament\Resources\Backups\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;

class BackupForm
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
                TextInput::make('path')
                    ->required(),
                TextInput::make('size')
                    ->required()
                    ->numeric()
                    ->default(0),
                TextInput::make('medicine_count')
                    ->required()
                    ->numeric()
                    ->default(0),
            ]);
    }
}
