<?php

namespace App\Filament\Widgets;

use App\Models\Customer;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Filament\Widgets\TableWidget;
use Illuminate\Database\Eloquent\Builder;

class RecentCustomers extends TableWidget
{
    protected static ?int $sort = 4;

    protected int|string|array $columnSpan = 'full';

    protected static ?string $heading = 'Recent Customers';

    public function table(Table $table): Table
    {
        return $table
            ->query(
                fn (): Builder => Customer::query()->latest()->limit(10)
            )
            ->paginated(false)
            ->columns([
                TextColumn::make('name')
                    ->label('Name')
                    ->weight('bold')
                    ->searchable(),
                TextColumn::make('email')
                    ->searchable()
                    ->copyable()
                    ->icon('fas-envelope'),
                TextColumn::make('city')
                    ->badge()
                    ->color('gray'),
                TextColumn::make('status')
                    ->badge()
                    ->color(fn (string $state): string => match ($state) {
                        'active' => 'success',
                        'inactive' => 'gray',
                        'blocked' => 'danger',
                        default => 'gray',
                    }),
                TextColumn::make('plan.name')
                    ->label('Plan')
                    ->badge()
                    ->color('warning')
                    ->placeholder('Free'),
                TextColumn::make('created_at')
                    ->label('Joined')
                    ->since()
                    ->sortable(),
            ]);
    }
}
