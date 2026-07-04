<?php

namespace App\Console\Commands;

use App\Models\Plan;
use App\Services\PlayCatalogService;
use Illuminate\Console\Command;

class SyncPlansFromPlay extends Command
{
    protected $signature = 'plans:sync-from-play';

    protected $description = 'Pull the subscription catalog from Google Play and upsert it into the plans table';

    public function handle(PlayCatalogService $catalog): int
    {
        $this->info($catalog->isLive()
            ? 'Fetching catalog from Google Play…'
            : 'Google Play credentials not set — using dev fallback catalog.');

        $created = 0;
        $updated = 0;

        foreach ($catalog->list() as $item) {
            $plan = Plan::withTrashed()->firstWhere('product_id', $item['product_id']);

            if ($plan) {
                // Only refresh billing fields from Play; keep local metadata
                // (name/features/badge/sort) that admins manage in the panel.
                $plan->fill([
                    'billing_period' => $item['billing_period'],
                    'price' => $item['price'],
                    'currency' => $item['currency'],
                ]);
                if ($plan->isDirty()) {
                    $plan->save();
                    $updated++;
                }
            } else {
                Plan::create([
                    'name' => $item['name'],
                    'product_id' => $item['product_id'],
                    'billing_period' => $item['billing_period'],
                    'price' => $item['price'],
                    'currency' => $item['currency'],
                    'is_active' => true,
                    'is_best_value' => $item['billing_period'] === 'yearly',
                    'badge' => $item['billing_period'] === 'yearly' ? 'BEST VALUE' : null,
                    'sort_order' => 99,
                    'features' => [],
                ]);
                $created++;
            }
        }

        $this->info("Done. Created: {$created}, updated: {$updated}.");

        return self::SUCCESS;
    }
}
