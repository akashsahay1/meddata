<?php

namespace App\Filament\Resources\AppSettings\Schemas;

use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Textarea;
use Filament\Schemas\Schema;

class AppSettingForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('key')
                    ->required(),
                Textarea::make('value')
                    ->default(null)
                    ->columnSpanFull(),
                TextInput::make('type')
                    ->required()
                    ->default('string'),
                TextInput::make('label')
                    ->default(null),
                TextInput::make('group')
                    ->required()
                    ->default('general'),
            ]);
    }
}
