<?php

namespace App\Filament\Resources\MedicineMasters\Tables;

use App\Models\MedicineMaster;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Enums\PaginationMode;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

/**
 * 100k+ rows: every search/filter/sort here hits an index, and pagination is
 * "simple" so no COUNT(*) over the whole table runs on each page load.
 */
class MedicineMastersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->weight('bold')
                    // Prefix match on the indexed normalised name.
                    ->searchable(query: fn (Builder $query, string $search): Builder => $query
                        ->where('name_norm', 'like', MedicineMaster::norm($search).'%')),
                TextColumn::make('manufacturer')
                    ->placeholder('-'),
                TextColumn::make('pack_size')
                    ->label('Pack size')
                    ->placeholder('-'),
                TextColumn::make('price')
                    ->money('INR')
                    ->placeholder('-'),
                TextColumn::make('barcode')
                    ->placeholder('-')
                    ->searchable(query: fn (Builder $query, string $search): Builder => $query
                        ->where('barcode', 'like', trim($search).'%')),
                TextColumn::make('source')
                    ->badge()
                    ->color(fn (string $state): string => match ($state) {
                        'seed' => 'gray',
                        'shop' => 'success',
                        'admin' => 'warning',
                        default => 'gray',
                    }),
                TextColumn::make('created_by_shop_id')
                    ->label('Shop ID')
                    ->placeholder('-'),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->toggleable(),
            ])
            ->filters([
                SelectFilter::make('source')
                    ->options([
                        'seed' => 'Seed (CSV)',
                        'shop' => 'Added by shop',
                        'admin' => 'Admin',
                    ]),
            ])
            // Search the whole phrase as one prefix (not word-by-word).
            ->splitSearchTerms(false)
            ->defaultSort('id', 'desc')
            ->paginationMode(PaginationMode::Simple)
            ->paginated([25, 50, 100]);
    }
}
