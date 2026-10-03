<?php

namespace App\Filament\Resources\Shops\Schemas;

use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class ShopInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Section::make('Shop')
                    ->columns(3)
                    ->columnSpanFull()
                    ->schema([
                        TextEntry::make('name')
                            ->weight('bold'),
                        TextEntry::make('owner.name')
                            ->label('Owner'),
                        TextEntry::make('owner.email')
                            ->label('Owner email')
                            ->copyable(),
                        TextEntry::make('phone')
                            ->placeholder('-'),
                        TextEntry::make('gstin')
                            ->label('GSTIN')
                            ->placeholder('-'),
                        TextEntry::make('state_code')
                            ->label('State code')
                            ->placeholder('-'),
                        TextEntry::make('drug_license_no')
                            ->label('Drug licence no.')
                            ->placeholder('-'),
                        TextEntry::make('invoice_prefix')
                            ->label('Invoice prefix')
                            ->placeholder('-'),
                        TextEntry::make('seq')
                            ->label('Sync version')
                            ->numeric(),
                        TextEntry::make('address')
                            ->placeholder('-')
                            ->columnSpanFull(),
                        TextEntry::make('created_at')
                            ->label('Joined')
                            ->dateTime(),
                        TextEntry::make('updated_at')
                            ->label('Updated')
                            ->dateTime(),
                    ]),
            ]);
    }
}
