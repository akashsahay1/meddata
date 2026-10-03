<?php

namespace App\Filament\Widgets;

use App\Models\Shop;
use App\Models\ShopDevice;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Filament\Widgets\TableWidget;
use Illuminate\Database\Eloquent\Builder;

class RecentShops extends TableWidget
{
    protected static ?int $sort = 4;

    protected int|string|array $columnSpan = 'full';

    protected static ?string $heading = 'Recent Shops';

    public function table(Table $table): Table
    {
        return $table
            ->query(
                fn (): Builder => Shop::query()
                    ->with('owner')
                    // Product uses soft deletes, so withCount skips tombstones.
                    ->withCount(['products', 'devices'])
                    ->addSelect([
                        'last_sync_at' => ShopDevice::query()
                            ->selectRaw('MAX(last_sync_at)')
                            ->whereColumn('shop_devices.shop_id', 'shops.id'),
                    ])
                    ->latest()
                    ->limit(10)
            )
            ->paginated(false)
            ->columns([
                TextColumn::make('name')
                    ->label('Shop')
                    ->weight('bold'),
                TextColumn::make('owner.name')
                    ->label('Owner')
                    ->description(fn (Shop $record): ?string => $record->owner?->email),
                TextColumn::make('phone')
                    ->placeholder('-'),
                TextColumn::make('products_count')
                    ->label('Products')
                    ->numeric(),
                TextColumn::make('devices_count')
                    ->label('Devices')
                    ->numeric(),
                TextColumn::make('last_sync_at')
                    ->label('Last sync')
                    ->since()
                    ->placeholder('Never'),
                TextColumn::make('created_at')
                    ->label('Joined')
                    ->since(),
            ]);
    }
}
