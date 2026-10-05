<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Bill;
use App\Models\PurchaseReturn;
use App\Models\SaleReturn;
use App\Services\ReturnService;
use App\Services\ShopService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/** Sale returns (credit notes) and purchase returns (debit notes). */
class ReturnController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly ReturnService $returns,
    ) {}

    /** GET /sale-returns?from=&to=&bill_id=&party_id=&page= */
    public function saleIndex(Request $request): JsonResponse
    {
        return $this->index($request, SaleReturn::query(), 'bill_id');
    }

    /** GET /purchase-returns?from=&to=&purchase_id=&party_id=&page= */
    public function purchaseIndex(Request $request): JsonResponse
    {
        return $this->index($request, PurchaseReturn::query(), 'purchase_id');
    }

    /**
     * POST /sale-returns
     * {id, device_id?, bill_id, refund_mode? (credit|cash|upi|card|bank), reason?,
     *  lines: [{bill_item_id, qty_units}]}
     * 201 {sale_return, batches} | 200 + replayed
     * 422 return_exceeds_sold (lines: sold, returned, returnable) / bill_cancelled / refund_mode; 404 bill
     */
    public function saleStore(Request $request): JsonResponse
    {
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'device_id' => ['nullable', 'string', 'max:64'],
            'bill_id' => ['required', 'uuid'],
            'refund_mode' => ['nullable', Rule::in(SaleReturn::REFUND_MODES)],
            'reason' => ['nullable', 'string', 'max:255'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.bill_item_id' => ['required', 'integer'],
            'lines.*.qty_units' => ['required', 'integer', 'min:1', 'max:100000'],
        ]);
        $data['id'] = strtolower($data['id']);
        $user = $request->user();
        $shop = $this->shops->forUser($user);
        $bill = Bill::where('shop_id', $shop->id)->find(strtolower($data['bill_id']));
        abort_if($bill === null, 404, 'Bill not found.');

        [$note, $created, $stock] = $this->returns->saleReturn($shop, $user, $bill, $data);

        return response()->json(['sale_return' => $note->toApi(), 'batches' => $stock, 'replayed' => ! $created],
            $created ? 201 : 200);
    }

    /**
     * POST /purchase-returns
     * {id, device_id?, purchase_id? | party_id?, reason?,
     *  lines: [{purchase_item_id, qty}] against a purchase (qty in its packs), or
     *         [{batch_id, qty, rate_paise?, gst_rate_bp?, discount_bp?}] for a supplier (qty in stock units)}
     * 201 {purchase_return, batches} | 200 + replayed
     * 422 return_exceeds_bought / insufficient_stock / party_not_supplier / purchase_cancelled; 404 purchase
     */
    public function purchaseStore(Request $request): JsonResponse
    {
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'device_id' => ['nullable', 'string', 'max:64'],
            'purchase_id' => ['nullable', 'uuid', 'required_without:party_id'],
            'party_id' => ['nullable', 'uuid'],
            'reason' => ['nullable', 'string', 'max:255'],
            'lines' => ['required', 'array', 'min:1', 'max:300'],
            'lines.*.purchase_item_id' => ['nullable', 'integer'],
            'lines.*.batch_id' => ['nullable', 'uuid'],
            'lines.*.qty' => ['required', 'integer', 'min:1', 'max:1000000'],
            'lines.*.rate_paise' => ['nullable', 'integer', 'min:0', 'max:100000000000'],
            'lines.*.gst_rate_bp' => ['nullable', 'integer', 'min:0', 'max:2800'],
            'lines.*.discount_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
        ]);
        $data['id'] = strtolower($data['id']);
        foreach (['purchase_id', 'party_id'] as $key) {
            if (isset($data[$key])) {
                $data[$key] = strtolower($data[$key]);
            }
        }
        $user = $request->user();
        [$note, $created, $stock] = $this->returns->purchaseReturn($this->shops->forUser($user), $user, $data);

        return response()->json(['purchase_return' => $note->toApi(), 'batches' => $stock, 'replayed' => ! $created],
            $created ? 201 : 200);
    }

    /** GET /sale-returns/{id} */
    public function saleShow(Request $request, string $id): JsonResponse
    {
        return response()->json(['sale_return' => $this->find(SaleReturn::query(), $request, $id)->toApi()]);
    }

    /** GET /purchase-returns/{id} */
    public function purchaseShow(Request $request, string $id): JsonResponse
    {
        return response()->json(['purchase_return' => $this->find(PurchaseReturn::query(), $request, $id)->toApi()]);
    }

    // ---------------------------------------------------------------------

    private function index(Request $request, Builder $query, string $docKey): JsonResponse
    {
        $data = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            $docKey => ['nullable', 'uuid'],
            'party_id' => ['nullable', 'uuid'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $page = $query->where('shop_id', $shop->id)
            ->when($data['from'] ?? null, fn ($q, $d) => $q->where('return_date', '>=', $d))
            ->when($data['to'] ?? null, fn ($q, $d) => $q->where('return_date', '<=', $d))
            ->when($data[$docKey] ?? null, fn ($q, $v) => $q->where($docKey, strtolower($v)))
            ->when($data['party_id'] ?? null, fn ($q, $v) => $q->where('party_id', strtolower($v)))
            ->orderByDesc('return_date')->orderByDesc('seq')
            ->paginate((int) ($data['per_page'] ?? 30));

        return response()->json([
            'data' => array_map(fn ($n) => $n->toSummary(), $page->items()),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    private function find(Builder $query, Request $request, string $id): SaleReturn|PurchaseReturn
    {
        $shop = $this->shops->forUser($request->user());
        $note = Str::isUuid($id) ? $query->with('items')->where('shop_id', $shop->id)->find(strtolower($id)) : null;
        abort_if($note === null, 404, 'Return not found.');

        return $note;
    }
}
