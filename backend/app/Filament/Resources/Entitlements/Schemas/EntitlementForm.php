<?php

namespace App\Filament\Resources\Entitlements\Schemas;

use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Schemas\Schema;

class EntitlementForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('device_id')
                    ->required(),
                Select::make('plan_id')
                    ->relationship('plan', 'name')
                    ->default(null),
                TextInput::make('product_id')
                    ->default(null),
                TextInput::make('status')
                    ->required()
                    ->default('expired'),
                DateTimePicker::make('expiry_time'),
                Toggle::make('is_premium')
                    ->required(),
            ]);
    }
}
