<?php

namespace App\Filament\Resources\Medicines\Schemas;

use Filament\Forms\Components\DatePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;

class MedicineForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Select::make('store_id')
                    ->relationship('store', 'store_name')
                    ->searchable()
                    ->preload()
                    ->default(null),
                TextInput::make('name')
                    ->required(),
                TextInput::make('brand')
                    ->default(null),
                TextInput::make('category')
                    ->default(null),
                TextInput::make('batch_no')
                    ->default(null),
                TextInput::make('barcode')
                    ->default(null),
                TextInput::make('quantity')
                    ->required()
                    ->numeric()
                    ->default(0),
                TextInput::make('unit')
                    ->default(null),
                DatePicker::make('expiry_date'),
                TextInput::make('selling_price')
                    ->required()
                    ->numeric()
                    ->default(0.0)
                    ->prefix('₹'),
            ]);
    }
}
