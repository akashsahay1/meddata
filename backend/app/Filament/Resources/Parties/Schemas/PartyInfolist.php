<?php

namespace App\Filament\Resources\Parties\Schemas;

use App\Filament\Resources\Parties\Tables\PartiesTable;
use App\Models\Party;
use App\Services\PartyLedger;
use App\Support\GstStates;
use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class PartyInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Section::make('Party')
                    ->columns(3)
                    ->columnSpanFull()
                    ->schema([
                        TextEntry::make('name')
                            ->weight('bold'),
                        TextEntry::make('type')
                            ->badge(),
                        TextEntry::make('shop.name')
                            ->label('Shop'),
                        TextEntry::make('phone')
                            ->placeholder('-'),
                        TextEntry::make('gstin')
                            ->label('GSTIN')
                            ->placeholder('-')
                            ->copyable(),
                        TextEntry::make('state_code')
                            ->label('State')
                            ->formatStateUsing(fn (string $state): string => $state.' - '.GstStates::name($state))
                            ->placeholder('-'),
                        TextEntry::make('address')
                            ->placeholder('-'),
                        TextEntry::make('notes')
                            ->placeholder('-'),
                        TextEntry::make('deleted_at')
                            ->label('Deleted')
                            ->dateTime()
                            ->placeholder('-'),
                    ]),
                Section::make('Account')
                    ->columns(3)
                    ->columnSpanFull()
                    ->schema([
                        TextEntry::make('opening_balance_paise')
                            ->label('Opening balance')
                            ->formatStateUsing(fn ($state): string => PartiesTable::balance((int) $state)),
                        TextEntry::make('balance')
                            ->label('Balance now')
                            ->state(fn (Party $record): string => PartiesTable::balance(app(PartyLedger::class)->balance($record)))
                            ->weight('bold'),
                        TextEntry::make('created_at')
                            ->label('Added')
                            ->dateTime(),
                    ]),
            ]);
    }
}
