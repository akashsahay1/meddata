<?php

namespace App\Services;

use App\Models\Bill;
use App\Models\Shop;
use Illuminate\Support\Facades\DB;

/**
 * Gross profit from the shop's bills over a date range.
 *
 * Revenue is each line's taxable value (price excluding GST, after the
 * line discount) - GST collected is not the shop's income. Cost is the
 * units sold x the batch's purchase rate, which is entered excluding GST
 * (the PTR / rate column of a purchase invoice; GST paid on purchases is
 * claimed back as input tax credit). It is the batch's current rate, so
 * correcting a missing or wrong rate also corrects past profit.
 *
 * A batch without a purchase rate (0) has an unknown cost: its lines are
 * listed separately and left out of cost, profit and margin, instead of
 * being counted as 100% margin. Cancelled bills are excluded.
 */
class ProfitReportService
{
    /** Longest range one request may cover (days, inclusive). */
    public const MAX_DAYS = 366;

    /**
     * @return array<string, mixed>
     */
    public function build(Shop $shop, string $from, string $to): array
    {
        // One row per bill date x batch: what was sold, for how much, and
        // the batch's purchase rate (a deleted batch's rate still counts).
        $rows = DB::table('bill_items as i')
            ->join('bills as b', 'b.id', '=', 'i.bill_id')
            ->leftJoin('batches as bt', fn ($j) => $j->on('bt.id', '=', 'i.batch_id')->on('bt.shop_id', '=', 'b.shop_id'))
            ->leftJoin('products as p', fn ($j) => $j->on('p.id', '=', 'i.product_id')->on('p.shop_id', '=', 'b.shop_id'))
            ->where('b.shop_id', $shop->id)
            ->where('b.status', Bill::STATUS_FINAL)
            ->where('b.bill_date', '>=', $from)
            ->where('b.bill_date', '<=', $to)
            ->groupBy('b.bill_date', 'i.batch_id', 'i.product_id')
            ->selectRaw('b.bill_date AS bill_date, i.batch_id AS batch_id, i.product_id AS product_id,
                MAX(i.name) AS name, MAX(i.batch_no) AS batch_no, MAX(p.name) AS product_name,
                MAX(p.category) AS category, SUM(i.qty_units) AS qty,
                SUM(i.taxable_paise) AS revenue, SUM(i.total_paise) AS sales,
                MAX(bt.purchase_rate_paise) AS rate')
            ->orderBy('b.bill_date')
            ->get();

        $bills = Bill::query()->where('shop_id', $shop->id)
            ->where('status', Bill::STATUS_FINAL)
            ->where('bill_date', '>=', $from)
            ->where('bill_date', '<=', $to)
            ->count();

        $total = $this->bucket();
        $days = $products = $categories = $unknown = [];

        foreach ($rows as $r) {
            $date = substr((string) $r->bill_date, 0, 10);
            $qty = (int) $r->qty;
            $revenue = (int) $r->revenue;
            $sales = (int) $r->sales;
            $rate = (int) ($r->rate ?? 0);
            $cost = $rate > 0 ? $qty * $rate : null;
            $name = (string) ($r->product_name ?? $r->name);
            $category = trim((string) ($r->category ?? '')) ?: 'Uncategorised';

            $this->add($total, $qty, $revenue, $sales, $cost);
            $days[$date] ??= $this->bucket(['date' => $date]);
            $this->add($days[$date], $qty, $revenue, $sales, $cost);
            $products[$r->product_id] ??= $this->bucket([
                'product_id' => $r->product_id, 'name' => $name, 'category' => $category,
            ]);
            $this->add($products[$r->product_id], $qty, $revenue, $sales, $cost);
            $categories[$category] ??= $this->bucket(['category' => $category]);
            $this->add($categories[$category], $qty, $revenue, $sales, $cost);

            if ($cost === null) {
                $unknown[$r->batch_id] ??= [
                    'product_id' => $r->product_id, 'batch_id' => $r->batch_id, 'name' => $name,
                    'batch_no' => $r->batch_no, 'qty_units' => 0, 'revenue_paise' => 0,
                ];
                $unknown[$r->batch_id]['qty_units'] += $qty;
                $unknown[$r->batch_id]['revenue_paise'] += $revenue;
            }
        }

        $byRevenue = fn (array $a, array $b) => [$b['revenue_paise'], $a['name'] ?? $a['category']]
            <=> [$a['revenue_paise'], $b['name'] ?? $b['category']];
        $products = array_values($products);
        usort($products, $byRevenue);
        $categories = array_values($categories);
        usort($categories, $byRevenue);
        $unknown = array_values($unknown);
        usort($unknown, fn ($a, $b) => $b['revenue_paise'] <=> $a['revenue_paise']);

        return [
            'from' => $from,
            'to' => $to,
            'basis' => [
                'revenue' => 'taxable value: price excluding GST, after discount',
                'cost' => "qty x batch purchase rate (excluding GST, the batch's current rate)",
            ],
            'totals' => $this->finish($total) + ['bills' => $bills],
            'by_day' => array_map(fn ($d) => $this->finish($d), array_values($days)),
            'by_product' => array_map(fn ($p) => $this->finish($p), $products),
            'by_category' => array_map(fn ($c) => $this->finish($c), $categories),
            'unknown_cost' => $unknown,
        ];
    }

    private function bucket(array $keys = []): array
    {
        return $keys + [
            'qty_units' => 0,
            'revenue_paise' => 0, // excl. GST, after discount
            'sales_paise' => 0, // what customers paid, incl. GST
            'costed_revenue_paise' => 0, // revenue of lines with a known cost
            'cost_paise' => 0,
            'unknown_cost_qty_units' => 0,
            'unknown_cost_revenue_paise' => 0,
        ];
    }

    private function add(array &$b, int $qty, int $revenue, int $sales, ?int $cost): void
    {
        $b['qty_units'] += $qty;
        $b['revenue_paise'] += $revenue;
        $b['sales_paise'] += $sales;
        if ($cost === null) {
            $b['unknown_cost_qty_units'] += $qty;
            $b['unknown_cost_revenue_paise'] += $revenue;
        } else {
            $b['costed_revenue_paise'] += $revenue;
            $b['cost_paise'] += $cost;
        }
    }

    /** Adds profit (lines with a known cost) and margin in basis points. */
    private function finish(array $b): array
    {
        $profit = $b['costed_revenue_paise'] - $b['cost_paise'];
        $b['profit_paise'] = $profit;
        // null when nothing in the bucket has a known cost.
        $b['margin_bp'] = $b['costed_revenue_paise'] > 0
            ? (int) round($profit * 10000 / $b['costed_revenue_paise'])
            : null;

        return $b;
    }
}
