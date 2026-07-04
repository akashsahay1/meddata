<?php

namespace App\Filament\Widgets;

use App\Models\Medicine;
use Filament\Widgets\ChartWidget;
use Illuminate\Support\Facades\DB;

class MedicineCategoryChart extends ChartWidget
{
    protected ?string $heading = 'Medicines by Category';

    protected static ?int $sort = 3;

    protected function getData(): array
    {
        $rows = Medicine::query()
            ->select('category', DB::raw('COUNT(*) as total'))
            ->groupBy('category')
            ->orderByDesc('total')
            ->limit(8)
            ->get();

        $labels = $rows->map(fn ($r) => $r->category ?: 'Uncategorised')->all();
        $data = $rows->pluck('total')->all();

        // A distinct colour per slice (doughnut is a visual dashboard element,
        // separate from the strictly black-and-white mobile app).
        $palette = [
            '#f59e0b', '#3b82f6', '#10b981', '#ef4444',
            '#8b5cf6', '#ec4899', '#14b8a6', '#6b7280',
        ];

        return [
            'datasets' => [
                [
                    'label' => 'Medicines',
                    'data' => $data,
                    'backgroundColor' => array_slice($palette, 0, count($data)),
                    'borderWidth' => 0,
                ],
            ],
            'labels' => $labels,
        ];
    }

    protected function getType(): string
    {
        return 'doughnut';
    }
}
