<?php

namespace App\Filament\Resources\Bills\Schemas;

use App\Models\Bill;
use App\Support\GstStates;
use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class BillInfolist
{
    public static function configure(Schema $schema): Schema
    {
        $money = fn (string $field, string $label): TextEntry => TextEntry::make($field)
            ->label($label)
            ->money('INR', divideBy: 100);

        return $schema
            ->components([
                Section::make('Invoice')
                    ->columns(3)
                    ->columnSpanFull()
                    ->schema([
                        TextEntry::make('invoice_no')
                            ->label('Invoice no.')
                            ->weight('bold')
                            ->copyable(),
                        TextEntry::make('bill_date')
                            ->label('Date')
                            ->date(),
                        TextEntry::make('status')
                            ->badge()
                            ->color(fn (string $state): string => $state === Bill::STATUS_CANCELLED ? 'danger' : 'success'),
                        TextEntry::make('shop.name')
                            ->label('Shop'),
                        TextEntry::make('payment_mode')
                            ->label('Payment')
                            ->formatStateUsing(fn (string $state): string => strtoupper($state)),
                        TextEntry::make('created_at')
                            ->label('Created')
                            ->dateTime(),
                        TextEntry::make('device_id')
                            ->label('Device')
                            ->placeholder('-'),
                        TextEntry::make('user.email')
                            ->label('Billed by')
                            ->placeholder('-'),
                    ]),
                Section::make('Customer')
                    ->columns(3)
                    ->columnSpanFull()
                    ->schema([
                        TextEntry::make('customer_name')
                            ->label('Name')
                            ->placeholder('Walk-in'),
                        TextEntry::make('customer_phone')
                            ->label('Phone')
                            ->placeholder('-'),
                        TextEntry::make('customer_gstin')
                            ->label('GSTIN')
                            ->placeholder('-'),
                        TextEntry::make('place_of_supply')
                            ->label('Place of supply')
                            ->formatStateUsing(fn (string $state): string => $state.' - '.GstStates::name($state))
                            ->placeholder('-'),
                        TextEntry::make('is_inter_state')
                            ->label('Tax')
                            ->formatStateUsing(fn ($state): string => $state ? 'IGST (inter-state)' : 'CGST + SGST'),
                        TextEntry::make('customer_address')
                            ->label('Address')
                            ->placeholder('-'),
                    ]),
                Section::make('Totals')
                    ->columns(4)
                    ->columnSpanFull()
                    ->schema([
                        $money('subtotal_paise', 'MRP value'),
                        $money('discount_paise', 'Discount'),
                        $money('taxable_paise', 'Taxable value'),
                        $money('cgst_paise', 'CGST'),
                        $money('sgst_paise', 'SGST'),
                        $money('igst_paise', 'IGST'),
                        $money('round_off_paise', 'Round off'),
                        $money('total_paise', 'Total')->weight('bold'),
                    ]),
                Section::make('Cancellation')
                    ->columns(3)
                    ->columnSpanFull()
                    ->visible(fn (Bill $record): bool => $record->isCancelled())
                    ->schema([
                        TextEntry::make('cancelled_at')
                            ->label('Cancelled')
                            ->dateTime(),
                        TextEntry::make('cancel_reason')
                            ->label('Reason')
                            ->placeholder('-'),
                    ]),
            ]);
    }
}
