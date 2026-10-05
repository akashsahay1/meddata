<?php

namespace App\Services;

use App\Models\MedicineMaster;
use App\Models\Product;
use App\Models\Shop;
use App\Support\MedicineNameKey;
use Illuminate\Support\Collection;

/**
 * Suggests, for each extracted invoice line, the shop's own product it most
 * likely is (so the app adds a new batch of it) and the master-catalog
 * medicine. Barcode first, then the exact normalised name, then a loose name
 * match (MedicineNameKey). A suggestion only: the user confirms in the app.
 */
class InvoiceProductMatcher
{
    /** @param  list<array>  $items  normalised invoice lines */
    public function annotate(Shop $shop, array $items): array
    {
        $products = Product::query()
            ->where('shop_id', $shop->id)
            ->orderBy('created_at')
            ->get(['id', 'name', 'name_norm', 'manufacturer', 'barcode']);
        $signatures = $products->mapWithKeys(fn (Product $p) => [$p->id => MedicineNameKey::signature($p->name)]);

        foreach ($items as $i => $item) {
            $product = $this->product($products, $signatures, $item);
            $master = $this->master($item);
            $items[$i]['match'] = [
                'product_id' => $product?->id,
                'product_name' => $product?->name,
                'master_id' => $master?->id,
                'master_name' => $master?->name,
                'master_manufacturer' => $master?->manufacturer,
            ];
        }

        return $items;
    }

    private function product(Collection $products, Collection $signatures, array $item): ?Product
    {
        $barcode = $item['barcode'] ?? null;
        if ($barcode !== null) {
            $hit = $products->first(fn (Product $p) => $p->barcode !== null
                && strcasecmp(trim($p->barcode), $barcode) === 0);
            if ($hit) {
                return $hit;
            }
        }

        $norm = Product::normalizeName($item['product_name']);
        $exact = $products->filter(fn (Product $p) => $p->name_norm === $norm);
        if ($exact->isEmpty()) {
            $want = MedicineNameKey::signature($item['product_name']);
            $exact = $products->filter(fn (Product $p) => MedicineNameKey::matches($want, $signatures[$p->id]));
        }

        return $this->preferMaker($exact, $item['manufacturer'] ?? null);
    }

    private function master(array $item): ?MedicineMaster
    {
        $barcode = $item['barcode'] ?? null;
        if ($barcode !== null) {
            $hit = MedicineMaster::where('barcode', $barcode)->orderBy('id')->first();
            if ($hit) {
                return $hit;
            }
        }

        $name = $item['product_name'];
        $ranked = fn ($q) => $q->orderBy('is_discontinued')
            ->orderByRaw("CASE WHEN source = 'seed' THEN 0 ELSE 1 END")
            ->orderBy('id');

        $exact = $ranked(MedicineMaster::where('name_norm', MedicineMaster::norm($name)))->limit(20)->get();
        if ($exact->isNotEmpty()) {
            return $this->preferMaker($exact, $item['manufacturer'] ?? null);
        }

        // Loose match among catalog names starting with the same first word.
        $first = MedicineNameKey::tokens($name)[0] ?? '';
        if (strlen($first) < 3 || ctype_digit($first)) {
            return null;
        }
        $want = MedicineNameKey::signature($name);
        $candidates = $ranked(MedicineMaster::where('name_norm', 'like', $first.'%'))
            ->limit(200)
            ->get(['id', 'name', 'manufacturer', 'is_discontinued', 'source'])
            ->filter(fn (MedicineMaster $m) => MedicineNameKey::matches($want, MedicineNameKey::signature($m->name)));

        return $this->preferMaker($candidates, $item['manufacturer'] ?? null);
    }

    /**
     * The candidate whose manufacturer matches the invoice's (often a short
     * code such as "MICRO" for "Micro Labs"), else the first one.
     */
    private function preferMaker(Collection $candidates, ?string $maker): mixed
    {
        $want = MedicineMaster::norm($maker);
        if ($want !== null) {
            $hit = $candidates->first(function ($c) use ($want) {
                $have = MedicineMaster::norm($c->manufacturer);

                return $have !== null && (str_starts_with($have, $want) || str_starts_with($want, $have));
            });
            if ($hit) {
                return $hit;
            }
        }

        return $candidates->first();
    }
}
