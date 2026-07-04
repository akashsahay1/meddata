<?php

namespace App\Filament\Resources\Customers\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Textarea;
use Filament\Schemas\Schema;

class CustomerForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('name')
                    ->required(),
                TextInput::make('email')
                    ->label('Email address')
                    ->email()
                    ->required(),
                TextInput::make('phone')
                    ->tel()
                    ->default(null),
                TextInput::make('city')
                    ->default(null),
                TextInput::make('state')
                    ->default(null),
                Select::make('status')
                    ->options(['active' => 'Active', 'inactive' => 'Inactive', 'blocked' => 'Blocked'])
                    ->default('active')
                    ->required(),
                Select::make('plan_id')
                    ->label('Plan')
                    ->relationship('plan', 'name')
                    ->searchable()
                    ->preload()
                    ->default(null),
                TextInput::make('device_id')
                    ->default(null),
                Textarea::make('notes')
                    ->default(null)
                    ->columnSpanFull(),
            ]);
    }
}
