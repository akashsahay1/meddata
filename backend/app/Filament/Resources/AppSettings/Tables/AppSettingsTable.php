<?php

namespace App\Filament\Resources\AppSettings\Tables;

use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use App\Models\AppSetting;
use Filament\Actions\EditAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;

class AppSettingsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('key')
                    ->searchable(),
                TextColumn::make('value')
                    ->searchable()
                    ->limit(40),
                TextColumn::make('type')
                    ->badge()
                    ->searchable(),
                TextColumn::make('label')
                    ->searchable(),
                TextColumn::make('group')
                    ->searchable(),
                TextColumn::make('created_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
                TextColumn::make('updated_at')
                    ->dateTime()
                    ->sortable()
                    ->toggleable(isToggledHiddenByDefault: true),
            ])
            ->filters([
                SelectFilter::make('group')
                    ->options(fn (): array => AppSetting::query()
                        ->whereNotNull('group')
                        ->distinct()
                        ->orderBy('group')
                        ->pluck('group', 'group')
                        ->all())
                    ->multiple(),
                SelectFilter::make('type')
                    ->options([
                        'string' => 'String',
                        'int' => 'Integer',
                        'bool' => 'Boolean',
                        'json' => 'JSON',
                    ])
                    ->multiple(),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ])
            ->defaultSort('group', 'asc')
            ->paginated([10, 25, 50, 100]);
    }
}
