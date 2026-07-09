<?php

namespace App\Filament\Resources\Payments\Schemas;

use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;

class PaymentForm
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
                Select::make('coupon_id')
                    ->relationship('coupon', 'id')
                    ->default(null),
                TextInput::make('amount')
                    ->required()
                    ->numeric()
                    ->default(0.0),
                TextInput::make('currency')
                    ->required()
                    ->default('INR'),
                TextInput::make('razorpay_order_id')
                    ->default(null),
                TextInput::make('razorpay_payment_id')
                    ->default(null),
                Select::make('status')
                    ->options(['created' => 'Created', 'paid' => 'Paid', 'failed' => 'Failed'])
                    ->default('created')
                    ->required(),
            ]);
    }
}
