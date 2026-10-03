<?php

namespace App\Filament\Resources\Shops\RelationManagers;

use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class DevicesRelationManager extends RelationManager
{
    protected static string $relationship = 'devices';

    protected static ?string $title = 'Devices';

    public function isReadOnly(): bool
    {
        return true;
    }

    public function table(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->placeholder('-'),
                TextColumn::make('platform')
                    ->badge()
                    ->color('gray')
                    ->placeholder('-'),
                TextColumn::make('app_version')
                    ->label('App version')
                    ->placeholder('-'),
                TextColumn::make('last_sync_at')
                    ->label('Last sync')
                    ->dateTime()
                    ->placeholder('Never')
                    ->sortable(),
                TextColumn::make('device_uuid')
                    ->label('Device ID')
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->defaultSort('last_sync_at', 'desc');
    }
}
