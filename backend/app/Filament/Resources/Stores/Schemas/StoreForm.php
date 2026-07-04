<?php

namespace App\Filament\Resources\Stores\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Schemas\Schema;

class StoreForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Select::make('customer_id')
                    ->relationship('customer', 'name')
                    ->searchable()
                    ->preload()
                    ->required(),
                TextInput::make('store_name')
                    ->required(),
                TextInput::make('phone')
                    ->tel()
                    ->default(null),
                TextInput::make('address')
                    ->default(null),
                TextInput::make('city')
                    ->default(null),
                TextInput::make('state')
                    ->default(null),
                TextInput::make('pincode')
                    ->default(null),
                TextInput::make('gstin')
                    ->default(null),
                Toggle::make('is_active')
                    ->default(true),
            ]);
    }
}
