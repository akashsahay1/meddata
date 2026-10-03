<?php

namespace App\Filament\Resources\Shops\RelationManagers;

use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

/** The shop's products (soft-deleted rows and batches are excluded by the SyncedRow scope). */
class ProductsRelationManager extends RelationManager
{
    protected static string $relationship = 'products';

    protected static ?string $title = 'Products';

    public function isReadOnly(): bool
    {
        return true;
    }

    public function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->weight('bold')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('manufacturer')
                    ->placeholder('-'),
                TextColumn::make('unit'),
                TextColumn::make('batches_sum_qty_units')
                    ->label('Total qty')
                    ->sum('batches', 'qty_units')
                    ->numeric()
                    ->default(0),
                TextColumn::make('batches_count')
                    ->label('Batches')
                    ->counts('batches')
                    ->numeric(),
                TextColumn::make('master_id')
                    ->label('Master ID')
                    ->placeholder('-'),
            ])
            ->defaultSort('name')
            ->paginated([10, 25, 50, 100]);
    }
}
