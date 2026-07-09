<?php

namespace App\Filament\Resources\Coupons\Tables;

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

class CouponsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('code')
                    ->searchable()
                    ->copyable()
                    ->weight('bold'),
                TextColumn::make('type')
                    ->badge()
                    ->color(fn (string $state) => $state === 'percentage' ? 'info' : 'warning'),
                TextColumn::make('value')
                    ->formatStateUsing(fn ($state, $record) => $record->type === 'percentage'
                        ? rtrim(rtrim((string) $state, '0'), '.') . '%'
                        : '₹' . rtrim(rtrim((string) $state, '0'), '.'))
                    ->sortable(),
                TextColumn::make('used_count')
                    ->label('Used')
                    ->formatStateUsing(fn ($state, $record) => $record->max_uses
                        ? "{$state} / {$record->max_uses}"
                        : (string) $state)
                    ->sortable(),
                TextColumn::make('min_amount')
                    ->money('INR')
                    ->placeholder('—')
                    ->sortable(),
                TextColumn::make('plan.name')
                    ->label('Plan')
                    ->placeholder('All plans')
                    ->searchable(),
                TextColumn::make('valid_until')
                    ->dateTime()
                    ->placeholder('No expiry')
                    ->sortable(),
                IconColumn::make('is_active')
                    ->boolean()
                    ->sortable(),
                TextColumn::make('valid_from')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('deleted_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('type')
                    ->options(['percentage' => 'Percentage', 'flat' => 'Flat']),
                TernaryFilter::make('is_active')
                    ->label('Active status'),
                SelectFilter::make('plan_id')
                    ->label('Plan')
                    ->relationship('plan', 'name'),
                Filter::make('valid_until')
                    ->schema([
                        DatePicker::make('until_from')->label('Expires from'),
                        DatePicker::make('until_to')->label('Expires until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['until_from'] ?? null, fn (Builder $q, $d) => $q->whereDate('valid_until', '>=', $d))
                            ->when($data['until_to'] ?? null, fn (Builder $q, $d) => $q->whereDate('valid_until', '<=', $d));
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
            ->defaultSort('created_at', 'desc');
    }
}
