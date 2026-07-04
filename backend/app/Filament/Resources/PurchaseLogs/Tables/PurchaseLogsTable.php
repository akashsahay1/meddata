<?php

namespace App\Filament\Resources\PurchaseLogs\Tables;

use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use App\Models\PurchaseLog;
use Filament\Actions\EditAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class PurchaseLogsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('device_id')
                    ->searchable(),
                TextColumn::make('product_id')
                    ->searchable(),
                TextColumn::make('event')
                    ->badge()
                    ->searchable(),
                TextColumn::make('result')
                    ->badge()
                    ->searchable(),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('updated_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('product_id')
                    ->label('Product')
                    ->options(fn (): array => PurchaseLog::query()
                        ->whereNotNull('product_id')
                        ->distinct()
                        ->orderBy('product_id')
                        ->pluck('product_id', 'product_id')
                        ->all())
                    ->searchable()
                    ->multiple(),
                SelectFilter::make('event')
                    ->options(fn (): array => PurchaseLog::query()
                        ->whereNotNull('event')
                        ->distinct()
                        ->orderBy('event')
                        ->pluck('event', 'event')
                        ->all())
                    ->multiple(),
                SelectFilter::make('result')
                    ->options(fn (): array => PurchaseLog::query()
                        ->whereNotNull('result')
                        ->distinct()
                        ->orderBy('result')
                        ->pluck('result', 'result')
                        ->all())
                    ->multiple(),
                Filter::make('created_at')
                    ->schema([
                        DatePicker::make('created_from')->label('From'),
                        DatePicker::make('created_until')->label('Until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['created_from'], fn (Builder $q, $date) => $q->whereDate('created_at', '>=', $date))
                            ->when($data['created_until'], fn (Builder $q, $date) => $q->whereDate('created_at', '<=', $date));
                    }),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([10, 25, 50, 100]);
    }
}
