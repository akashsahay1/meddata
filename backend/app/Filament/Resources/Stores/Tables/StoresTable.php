<?php

namespace App\Filament\Resources\Stores\Tables;

use App\Models\Store;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Actions\ForceDeleteBulkAction;
use Filament\Actions\RestoreBulkAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class StoresTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('customer.name')
                    ->label('Customer')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('store_name')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('phone')
                    ->searchable(),
                TextColumn::make('address')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('city')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('state')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('pincode')
                    ->searchable(),
                TextColumn::make('gstin')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('medicines_count')
                    ->label('Medicines')
                    ->counts('medicines')
                    ->badge()
                    ->sortable(),
                IconColumn::make('is_active')
                    ->boolean()
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
                SelectFilter::make('customer_id')
                    ->label('Customer')
                    ->relationship('customer', 'name')
                    ->searchable()
                    ->preload()
                    ->multiple(),
                SelectFilter::make('city')
                    ->options(fn (): array => Store::query()
                        ->whereNotNull('city')
                        ->distinct()
                        ->orderBy('city')
                        ->pluck('city', 'city')
                        ->all())
                    ->searchable()
                    ->multiple(),
                SelectFilter::make('state')
                    ->options(fn (): array => Store::query()
                        ->whereNotNull('state')
                        ->distinct()
                        ->orderBy('state')
                        ->pluck('state', 'state')
                        ->all())
                    ->searchable()
                    ->multiple(),
                TernaryFilter::make('is_active')
                    ->label('Active status'),
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
            ->defaultSort('created_at', 'desc')
            ->paginated([10, 25, 50, 100]);
    }
}
