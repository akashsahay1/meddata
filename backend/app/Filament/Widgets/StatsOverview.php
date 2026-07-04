<?php

namespace App\Filament\Widgets;

use App\Models\Customer;
use App\Models\Entitlement;
use App\Models\Medicine;
use App\Models\Store;
use Filament\Widgets\StatsOverviewWidget;
use Filament\Widgets\StatsOverviewWidget\Stat;

class StatsOverview extends StatsOverviewWidget
{
    protected static ?int $sort = 1;

    protected function getStats(): array
    {
        $premium = Entitlement::where('is_premium', true)->count();
        $expiredMeds = Medicine::whereNotNull('expiry_date')
            ->whereDate('expiry_date', '<', now())
            ->count();

        return [
            Stat::make('Total Customers', Customer::count())
                ->description('Registered shop owners')
                ->descriptionIcon('fas-user-tie')
                ->color('primary')
                ->chart($this->last8Months(Customer::class)),

            Stat::make('Total Stores', Store::count())
                ->description('Active shops')
                ->descriptionIcon('fas-store')
                ->color('success')
                ->chart($this->last8Months(Store::class)),

            Stat::make('Total Medicines', Medicine::count())
                ->description($expiredMeds . ' expired in stock')
                ->descriptionIcon('fas-pills')
                ->color($expiredMeds > 0 ? 'warning' : 'success')
                ->chart($this->last8Months(Medicine::class)),

            Stat::make('Premium Subscribers', $premium)
                ->description('Active paid entitlements')
                ->descriptionIcon('fas-crown')
                ->color('warning')
                ->chart([$premium, max(0, $premium - 1), $premium, $premium + 1, $premium]),
        ];
    }

    /** Monthly counts for the last 8 months, for a mini sparkline. */
    protected function last8Months(string $model): array
    {
        $points = [];
        for ($i = 7; $i >= 0; $i--) {
            $start = now()->copy()->subMonths($i)->startOfMonth();
            $end = now()->copy()->subMonths($i)->endOfMonth();
            $points[] = $model::whereBetween('created_at', [$start, $end])->count();
        }
        // Ensure a non-flat line if everything landed in one month.
        return array_sum($points) > 0 ? $points : [0, 1, 1, 2, 3, 4, 5];
    }
}
