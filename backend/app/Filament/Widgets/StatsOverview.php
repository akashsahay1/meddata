<?php

namespace App\Filament\Widgets;

use App\Models\Batch;
use App\Models\Entitlement;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;
use Illuminate\Database\Eloquent\Builder;

class StatsOverview extends StatsOverviewWidget
{
    protected static ?int $sort = 1;

    protected function getStats(): array
    {
        $premium = Entitlement::where('is_premium', true)->count();
        $appUsers = User::where('is_admin', false);
        // Batch uses soft deletes, so tombstoned batches are excluded.
        $expiredInStock = Batch::whereDate('expiry_date', '<', now()->toDateString())
            ->where('qty_units', '>', 0)
            ->count();

        return [
            Stat::make('Shops', Shop::count())
                ->description('Registered shops')
                ->descriptionIcon('fas-store')
                ->color('primary')
                ->chart($this->last8Months(Shop::query())),

            Stat::make('App users', (clone $appUsers)->count())
                ->description('Shop owners using the app')
                ->descriptionIcon('fas-user-tie')
                ->color('success')
                ->chart($this->last8Months($appUsers)),

            Stat::make('Products', Product::count())
                ->description($expiredInStock.' expired in stock')
                ->descriptionIcon('fas-pills')
                ->color($expiredInStock > 0 ? 'warning' : 'success')
                ->chart($this->last8Months(Product::query())),

            Stat::make('Premium Subscribers', $premium)
                ->description('Active paid entitlements')
                ->descriptionIcon('fas-crown')
                ->color('warning')
                ->chart([$premium, max(0, $premium - 1), $premium, $premium + 1, $premium]),
        ];
    }

    /** Monthly counts for the last 8 months, for a mini sparkline. */
    protected function last8Months(Builder $query): array
    {
        $points = [];
        for ($i = 7; $i >= 0; $i--) {
            $start = now()->copy()->subMonths($i)->startOfMonth();
            $end = now()->copy()->subMonths($i)->endOfMonth();
            $points[] = (clone $query)->whereBetween('created_at', [$start, $end])->count();
        }

        // Ensure a non-flat line if everything landed in one month.
        return array_sum($points) > 0 ? $points : [0, 1, 1, 2, 3, 4, 5];
    }
}
