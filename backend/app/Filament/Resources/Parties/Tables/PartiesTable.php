<?php

namespace App\Filament\Resources\Parties\Tables;

use App\Models\Party;
use App\Services\PartyLedger;
use Filament\Actions\ViewAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class PartiesTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->modifyQueryUsing(fn (Builder $query): Builder => $query->with('shop'))
            ->columns([
                TextColumn::make('name')
                    ->weight('bold')
                    ->searchable()
                    ->description(fn (Party $record): ?string => $record->phone),
                TextColumn::make('shop.name')
                    ->label('Shop')
                    ->searchable(),
                TextColumn::make('type')
                    ->badge()
                    ->color(fn (string $state): string => match ($state) {
                        'customer' => 'success',
                        'supplier' => 'info',
                        default => 'gray',
                    }),
                TextColumn::make('gstin')
                    ->label('GSTIN')
                    ->placeholder('-')
                    ->searchable()
                    ->copyable(),
                TextColumn::make('state_code')
                    ->label('State')
                    ->placeholder('-'),
                TextColumn::make('balance')
                    ->label('Balance')
                    ->state(fn (Party $record): int => app(PartyLedger::class)->balance($record))
                    ->formatStateUsing(fn (int $state): string => self::balance($state)),
                TextColumn::make('created_at')
                    ->label('Added')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('type')
                    ->options(['customer' => 'Customer', 'supplier' => 'Supplier', 'both' => 'Both']),
                SelectFilter::make('shop')
                    ->relationship('shop', 'name')
                    ->searchable()
                    ->preload(),
                TrashedFilter::make(),
            ])
            ->recordActions([
                ViewAction::make(),
            ])
            ->defaultSort('name')
            ->paginated([10, 25, 50, 100]);
    }

    /** "₹1,234.00 to collect" / "₹50.00 to pay" / "Settled" (+ = the party owes the shop). */
    public static function balance(int $paise): string
    {
        if ($paise === 0) {
            return 'Settled';
        }

        return '₹'.number_format(abs($paise) / 100, 2).($paise > 0 ? ' to collect' : ' to pay');
    }
}
