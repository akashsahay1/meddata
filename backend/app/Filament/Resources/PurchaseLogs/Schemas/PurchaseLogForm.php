<?php

namespace App\Filament\Resources\PurchaseLogs\Schemas;

use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Textarea;
use Filament\Schemas\Schema;

class PurchaseLogForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('device_id')
                    ->required(),
                TextInput::make('product_id')
                    ->default(null),
                TextInput::make('event')
                    ->default(null),
                TextInput::make('result')
                    ->default(null),
                Textarea::make('payload')
                    ->default(null)
                    ->columnSpanFull(),
            ]);
    }
}
