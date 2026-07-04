<?php

namespace App\Filament\Widgets;

use App\Models\Customer;
use Filament\Widgets\ChartWidget;

class CustomerGrowthChart extends ChartWidget
{
    protected ?string $heading = 'Customer Growth (last 8 months)';

    protected static ?int $sort = 2;

    protected function getData(): array
    {
        $labels = [];
        $newPerMonth = [];
        $cumulative = [];
        $runningTotal = 0;

        // Base = customers created before the 8-month window (so cumulative is accurate).
        $windowStart = now()->copy()->subMonths(7)->startOfMonth();
        $runningTotal = Customer::where('created_at', '<', $windowStart)->count();

        for ($i = 7; $i >= 0; $i--) {
            $start = now()->copy()->subMonths($i)->startOfMonth();
            $end = now()->copy()->subMonths($i)->endOfMonth();
            $count = Customer::whereBetween('created_at', [$start, $end])->count();

            $labels[] = $start->format('M Y');
            $newPerMonth[] = $count;
            $runningTotal += $count;
            $cumulative[] = $runningTotal;
        }

        return [
            'datasets' => [
                [
                    'label' => 'Total customers',
                    'data' => $cumulative,
                    'borderColor' => '#f59e0b',
                    'backgroundColor' => 'rgba(245, 158, 11, 0.15)',
                    'fill' => true,
                    'tension' => 0.35,
                ],
                [
                    'label' => 'New customers',
                    'data' => $newPerMonth,
                    'borderColor' => '#3b82f6',
                    'backgroundColor' => 'rgba(59, 130, 246, 0.15)',
                    'fill' => true,
                    'tension' => 0.35,
                ],
            ],
            'labels' => $labels,
        ];
    }

    protected function getType(): string
    {
        return 'line';
    }
}
