<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Purchase;
use App\Models\PurchaseReturnItem;
use App\Models\Shop;
use App\Services\BillingService;
use App\Services\PartyLedger;
use App\Services\PurchaseService;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Supplier bills (purchase entries). The server creates/attaches the
 * batches and records the stock movements; devices get them by sync pull.
 * (Named apart from PurchaseController, which is Google Play purchases.)
 */
class PurchaseEntryController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly PurchaseService $purchases,
        private readonly PartyLedger $ledger,
    ) {}

    /** GET /purchases?from=&to=&party_id=&status=&q=&page=&per_page= (by invoice date, newest first) */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            'party_id' => ['nullable', 'uuid'],
            'status' => ['nullable', Rule::in([Purchase::STATUS_FINAL, Purchase::STATUS_CANCELLED])],
            'q' => ['nullable', 'string', 'max:100'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $search = trim((string) ($data['q'] ?? ''));

        $base = Purchase::where('shop_id', $shop->id)
            ->when($data['from'] ?? null, fn ($q, $d) => $q->where('invoice_date', '>=', $d))
            ->when($data['to'] ?? null, fn ($q, $d) => $q->where('invoice_date', '<=', $d))
            ->when($data['party_id'] ?? null, fn ($q, $p) => $q->where('party_id', strtolower($p)))
            ->when($search !== '', function ($q) use ($search) {
                $like = '%'.addcslashes($search, '%_\\').'%';
                $q->where(fn ($w) => $w->where('supplier_invoice_no', 'like', $like)->orWhere('supplier_name', 'like', $like));
            });
        $final = (clone $base)->where('status', Purchase::STATUS_FINAL)
            ->selectRaw('COUNT(*) AS n, COALESCE(SUM(total_paise), 0) AS total')->first();
        $page = (clone $base)
            ->when($data['status'] ?? null, fn ($q, $s) => $q->where('status', $s))
            ->withCount('items')
            ->orderByDesc('invoice_date')
            ->orderByDesc('created_at')
            ->paginate((int) ($data['per_page'] ?? 30));

        return response()->json([
            'data' => array_map(fn (Purchase $p) => $p->toSummary(), $page->items()),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
            'summary' => ['count' => (int) $final->n, 'total_paise' => (int) $final->total],
        ]);
    }

    /**
     * POST /purchases
     * {id, device_id?, party_id, supplier_invoice_no, invoice_date, invoice_scan_id?, notes?,
     *  lines: [{product_id, product?: {name, manufacturer?, unit?, pack_size?, category?, barcode?},
     *           batch_id?, batch_no?, expiry_date, mfg_date?, qty, free_qty?, units_per_pack?,
     *           rate_paise, mrp_paise, discount_bp?, gst_rate_bp?, hsn?}]}
     *
     * 201 {purchase, batches} | 200 same + replayed for a retry
     * 422 party_not_supplier / duplicate_invoice / product_not_found / plan_limit / batch_mismatch / validation
     */
    public function store(Request $request): JsonResponse
    {
        $today = now(BillingService::TIMEZONE)->toDateString();
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'device_id' => ['nullable', 'string', 'max:64'],
            'party_id' => ['required', 'uuid'],
            'supplier_invoice_no' => ['required', 'string', 'max:32'],
            'invoice_date' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.$today],
            'invoice_scan_id' => ['nullable', 'integer'],
            'notes' => ['nullable', 'string', 'max:500'],
            'lines' => ['required', 'array', 'min:1', 'max:300'],
            'lines.*.product_id' => ['required', 'uuid'],
            'lines.*.product' => ['nullable', 'array'],
            'lines.*.product.name' => ['nullable', 'string', 'max:255'],
            'lines.*.product.manufacturer' => ['nullable', 'string', 'max:255'],
            'lines.*.product.unit' => ['nullable', 'string', 'max:32'],
            'lines.*.product.pack_size' => ['nullable', 'integer', 'min:1', 'max:100000'],
            'lines.*.product.category' => ['nullable', 'string', 'max:255'],
            'lines.*.product.barcode' => ['nullable', 'string', 'max:64'],
            'lines.*.batch_id' => ['nullable', 'uuid'],
            'lines.*.batch_no' => ['nullable', 'string', 'max:64'],
            'lines.*.expiry_date' => ['required', 'date_format:Y-m-d'],
            'lines.*.mfg_date' => ['nullable', 'date_format:Y-m-d'],
            'lines.*.qty' => ['required', 'integer', 'min:0', 'max:1000000'],
            'lines.*.free_qty' => ['nullable', 'integer', 'min:0', 'max:1000000'],
            'lines.*.units_per_pack' => ['nullable', 'integer', 'min:1', 'max:10000'],
            'lines.*.rate_paise' => ['required', 'integer', 'min:0', 'max:100000000000'],
            'lines.*.mrp_paise' => ['nullable', 'integer', 'min:0', 'max:100000000000'],
            'lines.*.discount_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
            'lines.*.gst_rate_bp' => ['nullable', 'integer', 'min:0', 'max:2800'],
            'lines.*.hsn' => ['nullable', 'string', 'max:16'],
        ]);
        $errors = [];
        foreach ($data['lines'] as $i => $line) {
            if ((int) $line['qty'] + (int) ($line['free_qty'] ?? 0) < 1) {
                $errors["lines.$i.qty"] = 'Enter a quantity.';
            }
            if (! empty($line['mfg_date']) && $line['mfg_date'] >= $line['expiry_date']) {
                $errors["lines.$i.expiry_date"] = 'The expiry must be after the manufacture date.';
            }
        }
        if ($errors) {
            throw ValidationException::withMessages($errors);
        }
        $data['id'] = strtolower($data['id']);
        $data['party_id'] = strtolower($data['party_id']);

        $user = $request->user();
        [$purchase, $created, $stock] = $this->purchases->create($this->shops->forUser($user), $user, $data);

        return response()->json([
            'purchase' => $this->full($purchase),
            'batches' => $stock,
            'replayed' => ! $created,
        ], $created ? 201 : 200);
    }

    /** GET /purchases/{id} */
    public function show(Request $request, string $purchase): JsonResponse
    {
        return response()->json(['purchase' => $this->full($this->find($this->shops->forUser($request->user()), $purchase))]);
    }

    /** POST /purchases/{id}/cancel {reason?, device_id?}: 422 has_returns / has_payments / insufficient_stock */
    public function cancel(Request $request, string $purchase): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['nullable', 'string', 'max:255'],
            'device_id' => ['nullable', 'string', 'max:64'],
        ]);
        $user = $request->user();
        $shop = $this->shops->forUser($user);
        [$model, $stock] = $this->purchases->cancel($shop, $user, $this->find($shop, $purchase),
            $data['reason'] ?? null, $data['device_id'] ?? null);

        return response()->json(['purchase' => $this->full($model), 'batches' => $stock]);
    }

    /** The purchase with what is still owed on it and how much of each line went back. */
    private function full(Purchase $purchase): array
    {
        $purchase->loadMissing('items');
        $returned = PurchaseReturnItem::whereIn('purchase_item_id', $purchase->items->pluck('id'))
            ->groupBy('purchase_item_id')->selectRaw('purchase_item_id, SUM(qty) AS q')->pluck('q', 'purchase_item_id');
        foreach ($purchase->items as $item) {
            $item->returned_qty = (int) ($returned[$item->id] ?? 0);
        }

        return $purchase->toApi([
            'outstanding_paise' => $purchase->isCancelled() ? 0 : $this->ledger->purchaseOutstanding($purchase),
        ]);
    }

    private function find(Shop $shop, string $id): Purchase
    {
        $purchase = Str::isUuid($id)
            ? Purchase::with('items')->where('shop_id', $shop->id)->find(strtolower($id))
            : null;
        abort_if($purchase === null, 404, 'Purchase not found.');

        return $purchase;
    }
}
