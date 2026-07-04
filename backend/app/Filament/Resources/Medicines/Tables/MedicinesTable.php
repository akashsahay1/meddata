<?php

namespace App\Filament\Resources\Medicines\Tables;

use App\Models\Medicine;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Actions\ForceDeleteBulkAction;
use Filament\Actions\RestoreBulkAction;
use Filament\Forms\Components\DatePicker;
use Filament\Forms\Components\TextInput;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class MedicinesTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('store.store_name')
                    ->label('Store')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('brand')
                    ->searchable(),
                TextColumn::make('category')
                    ->badge()
                    ->searchable()
                    ->sortable(),
                TextColumn::make('batch_no')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('barcode')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('quantity')
                    ->numeric()
                    ->sortable()
                    ->badge()
                    ->color(fn (int $state): string => $state <= 0 ? 'danger' : ($state < 10 ? 'warning' : 'success')),
                TextColumn::make('unit')
                    ->toggleable(),
                TextColumn::make('expiry_date')
                    ->date()
                    ->sortable()
                    ->badge()
                    ->color(fn ($state): string => $state === null
                        ? 'gray'
                        : ($state->isPast() ? 'danger' : ($state->diffInDays(now()) <= 30 ? 'warning' : 'success'))),
                TextColumn::make('selling_price')
                    ->money('INR')
                    ->sortable(),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('updated_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('deleted_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('store_id')
                    ->label('Store')
                    ->relationship('store', 'store_name')
                    ->searchable()
                    ->preload()
                    ->multiple(),
                SelectFilter::make('category')
                    ->options(fn (): array => Medicine::query()
                        ->whereNotNull('category')
                        ->distinct()
                        ->orderBy('category')
                        ->pluck('category', 'category')
                        ->all())
                    ->searchable()
                    ->multiple(),
                SelectFilter::make('unit')
                    ->options(fn (): array => Medicine::query()
                        ->whereNotNull('unit')
                        ->distinct()
                        ->orderBy('unit')
                        ->pluck('unit', 'unit')
                        ->all())
                    ->multiple(),
                Filter::make('expired')
                    ->label('Expired only')
                    ->toggle()
                    ->query(fn (Builder $query): Builder => $query->whereNotNull('expiry_date')->whereDate('expiry_date', '<', now())),
                Filter::make('expiring_soon')
                    ->label('Expiring within 30 days')
                    ->toggle()
                    ->query(fn (Builder $query): Builder => $query
                        ->whereNotNull('expiry_date')
                        ->whereDate('expiry_date', '>=', now())
                        ->whereDate('expiry_date', '<=', now()->addDays(30))),
                Filter::make('low_stock')
                    ->label('Low stock (< threshold)')
                    ->schema([
                        TextInput::make('threshold')
                            ->numeric()
                            ->default(10)
                            ->label('Quantity below'),
                    ])
                    ->query(fn (Builder $query, array $data): Builder => $query
                        ->when($data['threshold'] !== null && $data['threshold'] !== '', fn (Builder $q) => $q->where('quantity', '<', (int) $data['threshold']))),
                Filter::make('out_of_stock')
                    ->label('Out of stock')
                    ->toggle()
                    ->query(fn (Builder $query): Builder => $query->where('quantity', '<=', 0)),
                Filter::make('expiry_date')
                    ->schema([
                        DatePicker::make('expiry_from')->label('Expiry from'),
                        DatePicker::make('expiry_until')->label('Expiry until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['expiry_from'], fn (Builder $q, $date) => $q->whereDate('expiry_date', '>=', $date))
                            ->when($data['expiry_until'], fn (Builder $q, $date) => $q->whereDate('expiry_date', '<=', $date));
                    }),
                Filter::make('created_at')
                    ->schema([
                        DatePicker::make('created_from')->label('Created from'),
                        DatePicker::make('created_until')->label('Created until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['created_from'], fn (Builder $q, $date) => $q->whereDate('created_at', '>=', $date))
                            ->when($data['created_until'], fn (Builder $q, $date) => $q->whereDate('created_at', '<=', $date));
                    }),
                TrashedFilter::make(),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                    ForceDeleteBulkAction::make(),
                    RestoreBulkAction::make(),
                ]),
            ])
            ->defaultSort('expiry_date', 'asc')
            ->paginated([10, 25, 50, 100]);
    }
}
