<?php

namespace App\Filament\Resources\Devices\Tables;

use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class DevicesTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('device_id')
                    ->searchable(),
                TextColumn::make('user.name')
                    ->label('User')
                    ->searchable(),
                TextColumn::make('platform')
                    ->searchable(),
                TextColumn::make('app_version')
                    ->searchable(),
                TextColumn::make('last_seen_at')
                    ->dateTime()
                    ->sortable(),
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
                SelectFilter::make('platform')
                    ->options([
                        'android' => 'Android',
                        'ios' => 'iOS',
                    ])
                    ->multiple(),
                Filter::make('last_seen_at')
                    ->schema([
                        DatePicker::make('seen_from')->label('Last seen from'),
                        DatePicker::make('seen_until')->label('Last seen until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['seen_from'], fn (Builder $q, $date) => $q->whereDate('last_seen_at', '>=', $date))
                            ->when($data['seen_until'], fn (Builder $q, $date) => $q->whereDate('last_seen_at', '<=', $date));
                    }),
                Filter::make('created_at')
                    ->schema([
                        DatePicker::make('created_from')->label('Registered from'),
                        DatePicker::make('created_until')->label('Registered until'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['created_from'], fn (Builder $q, $date) => $q->whereDate('created_at', '>=', $date))
                            ->when($data['created_until'], fn (Builder $q, $date) => $q->whereDate('created_at', '<=', $date));
                    }),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ])
            ->defaultSort('last_seen_at', 'desc')
            ->paginated([10, 25, 50, 100]);
    }
}
