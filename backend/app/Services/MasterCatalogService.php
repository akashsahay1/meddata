<?php

namespace App\Services;

use App\Models\Batch;
use App\Models\MedicineMaster;
use App\Models\Product;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Support\Facades\Log;

/**
 * Grows the shared catalog from what shops add. When a shop's product is
 * synced it is linked to an existing catalog medicine (by the id the device
 * picked, by barcode, or by name + manufacturer); if there is none, it is
 * added to the catalog (source = 'shop') so every other shop can find it.
 */
class MasterCatalogService
{
    /** Max new catalog rows one shop may add per day (abuse guard). */
    public const DAILY_LIMIT_PER_SHOP = 200;

    /**
     * Link the product to the catalog, adding it if missing. Best-effort:
     * never let a catalog problem break the shop's sync.
     */
    public function linkProduct(Product $product, Shop $shop, User $user): void
    {
        try {
            $master = $this->find($product) ?? $this->add($product, $shop, $user);
            if (! $master) {
                return;
            }
            $this->fillGaps($master, $product);
            if ((int) $product->master_id !== (int) $master->id) {
                // Not a user edit: bump the pull version only, so devices get
                // the link without their pending edits conflicting.
                $product->master_id = $master->id;
                $product->version = $shop->nextVersion();
                $product->saveQuietly();
            }
        } catch (\Throwable $e) {
            Log::warning('Master catalog link failed: '.$e->getMessage(), ['product' => $product->id]);
        }
    }

    /** A catalog medicine added by a shop with no price yet takes the first MRP seen. */
    public function notePrice(Batch $batch): void
    {
        try {
            $masterId = Product::whereKey($batch->product_id)->value('master_id');
            if ($masterId && $batch->mrp_paise > 0) {
                MedicineMaster::whereKey($masterId)
                    ->where('source', 'shop')
                    ->whereNull('price')
                    ->update(['price' => $batch->mrp_paise / 100, 'updated_at' => now()]);
            }
        } catch (\Throwable $e) {
            Log::warning('Master catalog price fill failed: '.$e->getMessage());
        }
    }

    private function find(Product $product): ?MedicineMaster
    {
        if ($product->master_id) {
            $picked = MedicineMaster::find($product->master_id);
            if ($picked) {
                return $picked;
            }
        }

        if ($product->barcode) {
            $byBarcode = MedicineMaster::where('barcode', $product->barcode)->orderBy('id')->first();
            if ($byBarcode) {
                return $byBarcode;
            }
        }

        $name = MedicineMaster::norm($product->name);
        if (! $name) {
            return null;
        }
        $maker = MedicineMaster::norm($product->manufacturer);

        return MedicineMaster::where('name_norm', $name)
            ->when($maker, fn ($q) => $q->where('manufacturer_norm', $maker))
            ->where('is_discontinued', false)
            ->orderByRaw("CASE WHEN source = 'seed' THEN 0 ELSE 1 END")
            ->orderBy('id')
            ->first();
    }

    private function add(Product $product, Shop $shop, User $user): ?MedicineMaster
    {
        $today = MedicineMaster::where('created_by_shop_id', $shop->id)
            ->where('created_at', '>=', now()->startOfDay())
            ->count();
        if ($today >= self::DAILY_LIMIT_PER_SHOP) {
            return null;
        }

        $unit = trim((string) $product->unit);
        $pack = (int) $product->pack_size > 1 ? $product->pack_size.' '.$unit : $unit;

        return MedicineMaster::create([
            'name' => trim($product->name),
            'name_norm' => MedicineMaster::norm($product->name),
            'manufacturer' => $product->manufacturer ?: null,
            'manufacturer_norm' => MedicineMaster::norm($product->manufacturer),
            'pack_size' => $pack !== '' ? $pack : null,
            'composition' => $product->composition ?: null,
            'barcode' => $product->barcode ?: null,
            'hsn' => $product->hsn ?: null,
            'gst_rate_bp' => $product->gst_rate_bp,
            'source' => 'shop',
            'created_by_shop_id' => $shop->id,
            'created_by_user_id' => $user->id,
        ]);
    }

    /** Fill catalog fields the catalog lacks but the shop knows. */
    private function fillGaps(MedicineMaster $master, Product $product): void
    {
        $fill = [];
        foreach (['barcode', 'hsn', 'gst_rate_bp', 'composition'] as $field) {
            if (blank($master->{$field}) && filled($product->{$field})) {
                $fill[$field] = $product->{$field};
            }
        }
        if ($fill) {
            $master->forceFill($fill)->save();
        }
    }
}
