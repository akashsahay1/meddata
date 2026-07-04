<?php

namespace App\Filament\Resources\Entitlements\Tables;

use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use App\Models\Entitlement;
use Filament\Actions\EditAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TernaryFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class EntitlementsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('device_id')
                    ->searchable(),
                TextColumn::make('plan.name')
                    ->label('Plan')
                    ->badge()
                    ->searchable(),
                TextColumn::make('product_id')
                    ->searchable(),
                TextColumn::make('status')
                    ->badge()
                    ->colors([
                        'success' => 'active',
                        'danger' => 'expired',
                    ])
                    ->searchable(),
                TextColumn::make('expiry_time')
                    ->dateTime()
                    ->sortable(),
                IconColumn::make('is_premium')
                    ->boolean(),
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
                SelectFilter::make('status')
                    ->options([
                        'active' => 'Active',
                        'expired' => 'Expired',
                    ])
                    ->multiple(),
                SelectFilter::make('plan_id')
                    ->label('Plan')
                    ->relationship('plan', 'name')
                    ->preload()
                    ->multiple(),
                SelectFilter::make('product_id')
                    ->label('Product')
                    ->options(fn (): array => Entitlement::query()
                        ->whereNotNull('product_id')
                        ->distinct()
                        ->orderBy('product_id')
                        ->pluck('product_id', 'product_id')
                        ->all())
                    ->multiple(),
                TernaryFilter::make('is_premium')
                    ->label('Premium'),
                Filter::make('expiry_time')
                    ->schema([
                        DatePicker::make('expiry_from')->label('Expiry from'),
                        DatePicker::make('expiry_until')->label('Expiry until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['expiry_from'], fn (Builder $q, $date) => $q->whereDate('expiry_time', '>=', $date))
                            ->when($data['expiry_until'], fn (Builder $q, $date) => $q->whereDate('expiry_time', '<=', $date));
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
