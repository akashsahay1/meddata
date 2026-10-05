<?php

namespace App\Filament\Resources\Bills\RelationManagers;

use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

/** The bill's lines (one per batch sold), as invoiced. */
class ItemsRelationManager extends RelationManager
{
    protected static string $relationship = 'items';

    protected static ?string $title = 'Items';

    public function isReadOnly(): bool
    {
        return true;
    }

    public function table(Table $table): Table
    {
        $money = fn (string $field, string $label): TextColumn => TextColumn::make($field)
            ->label($label)
            ->money('INR', divideBy: 100);
        // Basis points as a percentage: 1250 -> "12.5%".
        $percent = fn (string $field, string $label): TextColumn => TextColumn::make($field)
            ->label($label)
            ->formatStateUsing(fn ($state): string => rtrim(rtrim(number_format(((int) $state) / 100, 2), '0'), '.').'%');

        return $table
            ->columns([
                TextColumn::make('line_no')
                    ->label('#'),
                TextColumn::make('name')
                    ->weight('bold'),
                TextColumn::make('hsn')
                    ->label('HSN')
                    ->placeholder('-'),
                TextColumn::make('batch_no')
                    ->label('Batch')
                    ->placeholder('-'),
                TextColumn::make('expiry_date')
                    ->label('Expiry')
                    ->date(),
                TextColumn::make('qty_units')
                    ->label('Qty')
                    ->numeric(),
                $money('mrp_paise', 'MRP'),
                $percent('discount_bp', 'Disc.'),
                $percent('gst_rate_bp', 'GST'),
                $money('taxable_paise', 'Taxable'),
                $money('total_paise', 'Amount'),
            ])
            ->defaultSort('line_no')
            ->paginated(false);
    }
}
