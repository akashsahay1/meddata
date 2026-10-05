<?php

namespace App\Filament\Resources\Shops\Schemas;

use App\Support\GstStates;
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
                        TextEntry::make('legal_name')
                            ->label('Legal name')
                            ->placeholder('-'),
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
                            ->label('State')
                            ->formatStateUsing(fn (string $state): string => $state.' - '.GstStates::name($state))
                            ->placeholder('-'),
                        TextEntry::make('drug_license_no')
                            ->label('Drug licence no.')
                            ->placeholder('-'),
                        TextEntry::make('invoice_prefix')
                            ->label('Invoice prefix')
                            ->placeholder('INV (default)'),
                        TextEntry::make('default_gst_rate_bp')
                            ->label('Default GST rate')
                            ->formatStateUsing(fn ($state): string => rtrim(rtrim(number_format(((int) $state) / 100, 2), '0'), '.').'%'),
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
