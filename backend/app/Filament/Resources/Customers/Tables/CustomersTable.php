<?php

namespace App\Filament\Resources\Customers\Tables;

use App\Models\Customer;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Actions\ForceDeleteBulkAction;
use Filament\Actions\RestoreBulkAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class CustomersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('email')
                    ->label('Email address')
                    ->searchable()
                    ->copyable()
                    ->sortable(),
                TextColumn::make('phone')
                    ->searchable(),
                TextColumn::make('city')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('state')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('status')
                    ->badge()
                    ->colors([
                        'success' => 'active',
                        'warning' => 'inactive',
                        'danger' => 'blocked',
                    ])
                    ->sortable(),
                TextColumn::make('plan.name')
                    ->label('Plan')
                    ->badge()
                    ->searchable(),
                TextColumn::make('stores_count')
                    ->label('Stores')
                    ->counts('stores')
                    ->badge()
                    ->sortable(),
                TextColumn::make('device_id')
                    ->searchable()
                    ->toggleable(isToggledHiddenByDefault: true),
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
                SelectFilter::make('status')
                    ->options([
                        'active' => 'Active',
                        'inactive' => 'Inactive',
                        'blocked' => 'Blocked',
                    ])
                    ->multiple(),
                SelectFilter::make('plan_id')
                    ->label('Plan')
                    ->relationship('plan', 'name')
                    ->multiple()
                    ->preload(),
                SelectFilter::make('city')
                    ->options(fn (): array => Customer::query()
                        ->whereNotNull('city')
                        ->distinct()
                        ->orderBy('city')
                        ->pluck('city', 'city')
                        ->all())
                    ->searchable()
                    ->multiple(),
                SelectFilter::make('state')
                    ->options(fn (): array => Customer::query()
                        ->whereNotNull('state')
                        ->distinct()
                        ->orderBy('state')
                        ->pluck('state', 'state')
                        ->all())
                    ->searchable()
                    ->multiple(),
                Filter::make('created_at')
                    ->schema([
                        DatePicker::make('created_from')->label('Registered from'),
                        DatePicker::make('created_until')->label('Registered until'),
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
