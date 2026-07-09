<?php

namespace App\Filament\Resources\Coupons\Schemas;

use Filament\Actions\Action;
use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Schemas\Schema;
use Illuminate\Support\Str;

class CouponForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                TextInput::make('code')
                    ->required()
                    ->unique(ignoreRecord: true)
                    ->helperText('Uppercase code the user enters in the app.')
                    ->suffixAction(
                        Action::make('generate')
                            ->icon('fas-dice')
                            ->tooltip('Generate a random code')
                            ->action(fn (callable $set) => $set('code', strtoupper(Str::random(8)))),
                    ),
                Select::make('type')
                    ->options(['percentage' => 'Percentage (%)', 'flat' => 'Flat (₹)'])
                    ->default('percentage')
                    ->required()
                    ->live(),
                TextInput::make('value')
                    ->required()
                    ->numeric()
                    ->default(0.0)
                    ->helperText('Percentage off, or flat ₹ amount depending on type.'),
                TextInput::make('max_uses')
                    ->numeric()
                    ->helperText('Blank = unlimited.')
                    ->default(null),
                TextInput::make('used_count')
                    ->numeric()
                    ->default(0)
                    ->disabled()
                    ->dehydrated(false),
                TextInput::make('min_amount')
                    ->numeric()
                    ->prefix('₹')
                    ->helperText('Minimum order amount required.')
                    ->default(null),
                Select::make('plan_id')
                    ->label('Restrict to plan')
                    ->relationship('plan', 'name')
                    ->searchable()
                    ->preload()
                    ->helperText('Blank = valid for all plans.')
                    ->default(null),
                DateTimePicker::make('valid_from'),
                DateTimePicker::make('valid_until'),
                Toggle::make('is_active')
                    ->default(true),
            ]);
    }
}
