<?php

namespace App\Filament\Resources\Shops\Tables;

use App\Models\ShopDevice;
use Filament\Actions\ViewAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class ShopsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn (Builder $query): Builder => $query
                ->with('owner')
                ->addSelect([
                    'last_sync_at' => ShopDevice::query()
                        ->selectRaw('MAX(last_sync_at)')
                        ->whereColumn('shop_devices.shop_id', 'shops.id'),
                ]))
            ->columns([
                TextColumn::make('name')
                    ->weight('bold')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('owner.email')
                    ->label('Owner email')
                    ->searchable()
                    ->copyable(),
                TextColumn::make('gstin')
                    ->label('GSTIN')
                    ->placeholder('-'),
                TextColumn::make('phone')
                    ->placeholder('-'),
                // Product uses soft deletes, so the count skips tombstones.
                TextColumn::make('products_count')
                    ->label('Products')
                    ->counts('products')
                    ->numeric()
                    ->sortable(),
                TextColumn::make('devices_count')
                    ->label('Devices')
                    ->counts('devices')
                    ->numeric()
                    ->sortable(),
                TextColumn::make('last_sync_at')
                    ->label('Last sync')
                    ->since()
                    ->dateTimeTooltip()
                    ->placeholder('Never')
                    ->sortable(query: fn (Builder $query, string $direction): Builder => $query->orderBy('last_sync_at', $direction)),
                TextColumn::make('created_at')
                    ->label('Joined')
                    ->dateTime()
                    ->sortable(),
            ])
            ->recordActions([
                ViewAction::make(),
            ])
            ->defaultSort('created_at', 'desc')
            ->paginated([10, 25, 50, 100]);
    }
}
