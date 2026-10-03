<?php

namespace App\Services;

use App\Models\AppSetting;
use App\Models\Batch;
use App\Models\PriceChange;
use App\Models\Product;
use App\Models\Shop;
use App\Models\StockMovement;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * Device <-> server sync for shop inventory.
 *
 * Push rules:
 * - Every mutation has its own id; re-sending it returns the stored result.
 * - Product/batch edits carry `base_version` = the row's `edit_version` the
 *   device saw; if another device edited the row since, it's a conflict and
 *   the current row is returned. Nothing is overwritten without the user
 *   choosing (prices!). Stock movements don't count as edits.
 * - Stock movements are insert-only; batch qty is recomputed from them.
 * - Batch price edits are recorded in price_changes.
 *
 * Pull: every changed row (including tombstones) has a unique, increasing
 * per-shop `version`, so devices page through changes with one cursor.
 */
class SyncService
{
    public const TABLES = [
        'products' => Product::class,
        'batches' => Batch::class,
        'stock_movements' => StockMovement::class,
        'price_changes' => PriceChange::class,
    ];

    public const PUSHABLE = ['products', 'batches', 'stock_movements'];

    private ?bool $premium = null;

    public function __construct(
        private readonly EntitlementService $entitlements,
        private readonly MasterCatalogService $catalog,
    ) {}

    /** Apply mutations in order; each in its own transaction. */
    public function push(Shop $shop, User $user, string $deviceId, array $mutations): array
    {
        $results = [];
        foreach ($mutations as $m) {
            $results[] = DB::transaction(fn () => $this->applyOnce($shop, $user, $deviceId, (array) $m));
        }

        return $results;
    }

    public function pull(Shop $shop, int $since, int $limit): array
    {
        $rows = [];
        foreach (self::TABLES as $table => $class) {
            $chunk = $class::withTrashed()
                ->where('shop_id', $shop->id)
                ->where('version', '>', $since)
                ->orderBy('version')
                ->limit($limit + 1)
                ->get();
            foreach ($chunk as $row) {
                $rows[] = [$table, $row];
            }
        }
        usort($rows, fn ($a, $b) => $a[1]->version <=> $b[1]->version);

        $hasMore = count($rows) > $limit;
        $page = array_slice($rows, 0, $limit);

        $changes = array_fill_keys(array_keys(self::TABLES), []);
        $next = $since;
        foreach ($page as [$table, $row]) {
            $changes[$table][] = $this->serialize($row);
            $next = max($next, (int) $row->version);
        }

        return [
            'changes' => $changes,
            'next' => $next,
            'has_more' => $hasMore,
            'server_version' => (int) Shop::whereKey($shop->id)->value('seq'),
        ];
    }

    public function serialize(Model $row): array
    {
        return $row->toArray();
    }

    // ---------------------------------------------------------------------

    private function applyOnce(Shop $shop, User $user, string $deviceId, array $m): array
    {
        $mutationId = (string) ($m['mutation_id'] ?? '');
        if (! Str::isUuid($mutationId)) {
            return ['mutation_id' => $mutationId, 'status' => 'rejected', 'reason' => 'bad_mutation_id'];
        }

        $stored = DB::table('sync_mutations')
            ->where('shop_id', $shop->id)
            ->where('mutation_id', $mutationId)
            ->value('result');
        if ($stored !== null) {
            return json_decode($stored, true);
        }

        $result = ['mutation_id' => $mutationId] + $this->apply($shop, $user, $deviceId, $m);

        DB::table('sync_mutations')->insert([
            'shop_id' => $shop->id,
            'mutation_id' => $mutationId,
            'result' => json_encode($result),
            'created_at' => now(),
        ]);

        return $result;
    }

    private function apply(Shop $shop, User $user, string $deviceId, array $m): array
    {
        $table = $m['table'] ?? null;
        $op = $m['op'] ?? null;
        $id = (string) ($m['id'] ?? '');

        if (! in_array($table, self::PUSHABLE, true)) {
            return $this->rejected('unknown_table');
        }
        if (! Str::isUuid($id)) {
            return $this->rejected('bad_id');
        }

        $class = self::TABLES[$table];
        $row = $class::withTrashed()->find($id);
        if ($row && (int) $row->shop_id !== (int) $shop->id) {
            return $this->rejected('id_conflict');
        }

        if ($table === 'stock_movements') {
            return $this->applyMovement($shop, $user, $deviceId, $id, $op, $row, (array) ($m['data'] ?? []));
        }

        $base = array_key_exists('base_version', $m) && $m['base_version'] !== null
            ? (int) $m['base_version'] : null;

        if ($op === 'delete') {
            return $this->applyDelete($shop, $deviceId, $row, $base);
        }
        if ($op !== 'upsert') {
            return $this->rejected('bad_op');
        }

        $data = array_intersect_key((array) ($m['data'] ?? []), array_flip($class::clientFields()));

        if (! $row) {
            if ($base !== null) {
                return $this->rejected('not_found');
            }

            return $this->insert($shop, $user, $deviceId, $class, $id, $data);
        }

        if ($row->trashed()) {
            return $this->conflict('deleted', $row);
        }
        if ($base === null || $base !== (int) $row->edit_version) {
            return $this->conflict('version_mismatch', $row);
        }

        return $this->update($shop, $user, $deviceId, $row, $data);
    }

    private function insert(Shop $shop, User $user, string $deviceId, string $class, string $id, array $data): array
    {
        $errors = $this->validate($class, $data, true);
        if ($errors) {
            return $this->rejected('invalid', $errors);
        }

        if ($class === Product::class && ! $this->canAddProduct($shop, $user)) {
            return $this->rejected('plan_limit');
        }
        if ($class === Batch::class && ! $this->productExists($shop, $data['product_id'])) {
            return $this->rejected('product_not_found');
        }

        /** @var Model $row */
        $row = new $class;
        $row->id = $id;
        $row->fill($data);
        $row->shop_id = $shop->id;
        $row->created_by = $user->id;
        $row->device_id = $deviceId;
        if ($row instanceof Product) {
            $row->name_norm = Product::normalizeName($row->name);
        }
        $row->version = $shop->nextVersion();
        $row->edit_version = $row->version;
        $row->save();

        if ($row instanceof Product) {
            $this->catalog->linkProduct($row, $shop, $user);
        } elseif ($row instanceof Batch) {
            $this->catalog->notePrice($row);
        }

        return ['status' => 'ok', 'version' => (int) $row->edit_version];
    }

    private function update(Shop $shop, User $user, string $deviceId, Model $row, array $data): array
    {
        unset($data['product_id']); // a batch cannot move to another product
        $errors = $this->validate($row::class, $data, false);
        if ($errors) {
            return $this->rejected('invalid', $errors);
        }

        $before = $row instanceof Batch ? $row->only(Batch::PRICE_FIELDS) : [];
        $row->fill($data);
        if ($row instanceof Product && $row->isDirty('name')) {
            $row->name_norm = Product::normalizeName($row->name);
        }
        if (! $row->isDirty()) {
            return ['status' => 'ok', 'version' => (int) $row->edit_version];
        }

        $row->device_id = $deviceId;
        $row->version = $shop->nextVersion();
        $row->edit_version = $row->version;
        $row->save();

        if ($row instanceof Batch) {
            foreach (Batch::PRICE_FIELDS as $field) {
                if ((int) $before[$field] !== (int) $row->{$field}) {
                    $change = new PriceChange;
                    $change->id = (string) Str::uuid();
                    $change->fill([
                        'shop_id' => $shop->id,
                        'batch_id' => $row->id,
                        'field' => $field,
                        'old_paise' => (int) $before[$field],
                        'new_paise' => (int) $row->{$field},
                        'created_by' => $user->id,
                        'device_id' => $deviceId,
                    ]);
                    $change->version = $shop->nextVersion();
                    $change->save();
                }
            }
        }

        return ['status' => 'ok', 'version' => (int) $row->edit_version];
    }

    private function applyDelete(Shop $shop, string $deviceId, ?Model $row, ?int $base): array
    {
        if (! $row) {
            return $this->rejected('not_found');
        }
        if ($row->trashed()) {
            return ['status' => 'ok', 'version' => (int) $row->edit_version];
        }
        if ($base === null || $base !== (int) $row->edit_version) {
            return $this->conflict('version_mismatch', $row);
        }

        $this->tombstone($shop, $deviceId, $row);
        if ($row instanceof Product) {
            Batch::where('shop_id', $shop->id)->where('product_id', $row->id)->get()
                ->each(fn (Batch $b) => $this->tombstone($shop, $deviceId, $b));
        }

        return ['status' => 'ok', 'version' => (int) $row->edit_version];
    }

    private function tombstone(Shop $shop, string $deviceId, Model $row): void
    {
        $row->device_id = $deviceId;
        $row->version = $shop->nextVersion();
        $row->edit_version = $row->version;
        $row->deleted_at = now();
        $row->save();
    }

    private function applyMovement(Shop $shop, User $user, string $deviceId, string $id, ?string $op, ?Model $row, array $data): array
    {
        if ($op !== 'upsert') {
            return $this->rejected('immutable');
        }
        if ($row) {
            return ['status' => 'ok', 'version' => (int) $row->version];
        }

        $data = array_intersect_key($data, array_flip(StockMovement::clientFields()));
        $errors = $this->validate(StockMovement::class, $data, true);
        if ($errors) {
            return $this->rejected('invalid', $errors);
        }

        $batch = Batch::where('shop_id', $shop->id)->find($data['batch_id']);
        if (! $batch) {
            return $this->rejected('batch_not_found');
        }

        $movement = new StockMovement;
        $movement->id = $id;
        $movement->fill($data);
        $movement->shop_id = $shop->id;
        $movement->product_id = $batch->product_id;
        $movement->created_by = $user->id;
        $movement->device_id = $deviceId;
        $movement->version = $shop->nextVersion();
        $movement->save();

        // Derived, never client-supplied: recompute and publish the batch qty.
        $batch->qty_units = (int) StockMovement::where('batch_id', $batch->id)->sum('delta_units');
        $batch->version = $shop->nextVersion();
        $batch->save();

        return [
            'status' => 'ok',
            'version' => (int) $movement->version,
            'batch_qty_units' => (int) $batch->qty_units,
            'negative_stock' => $batch->qty_units < 0,
        ];
    }

    // ---------------------------------------------------------------------

    private function validate(string $class, array $data, bool $creating): array
    {
        $req = $creating ? 'required' : 'sometimes';
        $rules = match ($class) {
            Product::class => [
                'name' => [$req, 'string', 'max:255'],
                'manufacturer' => ['nullable', 'string', 'max:255'],
                'category' => ['nullable', 'string', 'max:255'],
                'composition' => ['nullable', 'string', 'max:2000'],
                'unit' => ['nullable', 'string', 'max:32'],
                'pack_size' => ['nullable', 'integer', 'min:1', 'max:100000'],
                'hsn' => ['nullable', 'string', 'max:16'],
                'gst_rate_bp' => ['nullable', 'integer', 'min:0', 'max:2800'],
                'barcode' => ['nullable', 'string', 'max:64'],
                'low_stock_threshold_units' => ['nullable', 'integer', 'min:0'],
                'discount_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
                'master_id' => ['nullable', 'integer'],
                'notes' => ['nullable', 'string', 'max:2000'],
            ],
            Batch::class => [
                'product_id' => [$creating ? 'required' : 'prohibited', 'uuid'],
                'batch_no' => ['nullable', 'string', 'max:64'],
                'expiry_date' => [$req, 'date_format:Y-m-d'],
                'mfg_date' => ['nullable', 'date_format:Y-m-d'],
                'mrp_paise' => ['nullable', 'integer', 'min:0'],
                'purchase_rate_paise' => ['nullable', 'integer', 'min:0'],
            ],
            StockMovement::class => [
                'batch_id' => ['required', 'uuid'],
                'delta_units' => ['required', 'integer', 'not_in:0'],
                'reason' => ['required', 'in:'.implode(',', StockMovement::REASONS)],
                'ref_type' => ['nullable', 'string', 'max:32'],
                'ref_id' => ['nullable', 'uuid'],
                'occurred_at' => ['required', 'date'],
            ],
        };

        $v = Validator::make($data, $rules);

        return $v->fails() ? $v->errors()->toArray() : [];
    }

    private function productExists(Shop $shop, string $productId): bool
    {
        return Product::where('shop_id', $shop->id)->whereKey($productId)->exists();
    }

    /** Paid/trial shops are unlimited; otherwise the admin-set free limit applies. */
    private function canAddProduct(Shop $shop, User $user): bool
    {
        $this->premium ??= (bool) ($this->entitlements->payload($this->entitlements->forUser($user))['premium'] ?? false);
        if ($this->premium) {
            return true;
        }
        $limit = (int) AppSetting::get('free_tier_limit', 7);

        return Product::where('shop_id', $shop->id)->count() < $limit;
    }

    private function rejected(string $reason, array $errors = []): array
    {
        return array_filter(['status' => 'rejected', 'reason' => $reason, 'errors' => $errors ?: null]);
    }

    private function conflict(string $reason, Model $row): array
    {
        return ['status' => 'conflict', 'reason' => $reason, 'row' => $this->serialize($row)];
    }
}
