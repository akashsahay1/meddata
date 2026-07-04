<?php

namespace App\Filament\Resources\Plans\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TagsInput;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Schemas\Schema;

class PlanForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('name')
                    ->required(),
                TextInput::make('product_id')
                    ->label('Product ID (Play Store)')
                    ->required()
                    ->unique(ignoreRecord: true),
                Select::make('billing_period')
                    ->options([
                        'free' => 'Free',
                        'monthly' => 'Monthly',
                        'yearly' => 'Yearly',
                        'lifetime' => 'Lifetime',
                    ])
                    ->required(),
                TextInput::make('price')
                    ->required()
                    ->numeric()
                    ->default(0.0)
                    ->prefix('₹'),
                TextInput::make('currency')
                    ->required()
                    ->default('INR'),
                TextInput::make('badge')
                    ->helperText('e.g. "BEST VALUE"')
                    ->default(null),
                Toggle::make('is_best_value')
                    ->default(false),
                Toggle::make('is_active')
                    ->default(true),
                TextInput::make('sort_order')
                    ->required()
                    ->numeric()
                    ->default(0),
                TagsInput::make('features')
                    ->label('Features')
                    ->helperText('Press Enter after each feature.')
                    ->placeholder('Add a feature')
                    ->columnSpanFull(),
            ]);
    }
}
