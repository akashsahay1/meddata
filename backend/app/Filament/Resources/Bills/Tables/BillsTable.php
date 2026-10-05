<?php

namespace App\Filament\Resources\Bills\Tables;

use App\Models\Bill;
use Filament\Actions\ViewAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class BillsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn (Builder $query): Builder => $query->with('shop')->withCount('items'))
            ->columns([
                TextColumn::make('invoice_no')
                    ->label('Invoice no.')
                    ->weight('bold')
                    ->searchable()
                    ->copyable(),
                TextColumn::make('shop.name')
                    ->label('Shop')
                    ->searchable(),
                TextColumn::make('bill_date')
                    ->label('Date')
                    ->date()
                    ->sortable(),
                TextColumn::make('customer_name')
                    ->label('Customer')
                    ->placeholder('Walk-in')
                    ->description(fn (Bill $record): ?string => $record->customer_phone)
                    ->searchable(),
                TextColumn::make('items_count')
                    ->label('Items')
                    ->numeric(),
                TextColumn::make('payment_mode')
                    ->label('Payment')
                    ->badge()
                    ->color('gray')
                    ->formatStateUsing(fn (string $state): string => strtoupper($state)),
                TextColumn::make('total_paise')
                    ->label('Total')
                    ->money('INR', divideBy: 100)
                    ->sortable(),
                TextColumn::make('status')
                    ->badge()
                    ->color(fn (string $state): string => $state === Bill::STATUS_CANCELLED ? 'danger' : 'success'),
                TextColumn::make('created_at')
                    ->label('Created')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->options([
                        Bill::STATUS_FINAL => 'Final',
                        Bill::STATUS_CANCELLED => 'Cancelled',
                    ]),
                SelectFilter::make('payment_mode')
                    ->label('Payment')
                    ->options(array_combine(Bill::PAYMENT_MODES, array_map('strtoupper', Bill::PAYMENT_MODES))),
                SelectFilter::make('shop')
                    ->relationship('shop', 'name')
                    ->searchable()
                    ->preload(),
                Filter::make('bill_date')
                    ->schema([
                        DatePicker::make('from')->label('From'),
                        DatePicker::make('until')->label('Until'),
                    ])
                    // bill_date is a plain Y-m-d string, so compare dates only.
                    ->query(fn (Builder $query, array $data): Builder => $query
                        ->when($data['from'] ?? null, fn (Builder $q, $d) => $q->where('bill_date', '>=', substr((string) $d, 0, 10)))
                        ->when($data['until'] ?? null, fn (Builder $q, $d) => $q->where('bill_date', '<=', substr((string) $d, 0, 10)))),
            ])
            ->recordActions([
                ViewAction::make(),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([10, 25, 50, 100]);
    }
}
