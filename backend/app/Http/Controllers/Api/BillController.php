<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Bill;
use App\Models\Shop;
use App\Rules\Gstin;
use App\Services\BillingService;
use App\Services\ShopService;
use App\Support\GstStates;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * GST bills of the user's shop. Billing is online-only: the device sends
 * the lines it showed (batch, qty, MRP and batch version) and the server
 * re-checks prices and stock, works out the tax and assigns the number.
 */
class BillController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly BillingService $billing,
    ) {}

    /**
     * GET /bills?from=Y-m-d&to=Y-m-d&status=&q=&page=&per_page=
     * Newest first. `summary` covers final bills in the date range / search.
     */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            'status' => ['nullable', Rule::in([Bill::STATUS_FINAL, Bill::STATUS_CANCELLED])],
            'q' => ['nullable', 'string', 'max:100'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $shop = $this->shops->forUser($request->user());

        $search = trim((string) ($data['q'] ?? ''));
        $base = Bill::query()
            ->where('shop_id', $shop->id)
            ->when($data['from'] ?? null, fn ($q, $d) => $q->where('bill_date', '>=', $d))
            ->when($data['to'] ?? null, fn ($q, $d) => $q->where('bill_date', '<=', $d))
            ->when($search !== '', function ($q) use ($search) {
                $like = '%'.addcslashes($search, '%_\\').'%';
                $q->where(fn ($w) => $w->where('invoice_no', 'like', $like)
                    ->orWhere('customer_name', 'like', $like)
                    ->orWhere('customer_phone', 'like', $like));
            });

        $final = (clone $base)->where('status', Bill::STATUS_FINAL)
            ->selectRaw('COUNT(*) AS bills, COALESCE(SUM(total_paise), 0) AS total')
            ->first();
        $page = (clone $base)
            ->when($data['status'] ?? null, fn ($q, $s) => $q->where('status', $s))
            ->withCount('items')
            ->orderByDesc('created_at')
            ->orderByDesc('seq')
            ->paginate((int) ($data['per_page'] ?? 30));

        return response()->json([
            'data' => array_map(fn (Bill $b) => $b->toSummary(), $page->items()),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
            'summary' => [
                'count' => (int) $final->bills,
                'total_paise' => (int) $final->total,
                'cancelled_count' => (clone $base)->where('status', Bill::STATUS_CANCELLED)->count(),
            ],
        ]);
    }

    /**
     * POST /bills
     * {id, device_id?, payment_mode, customer_name?, customer_phone?,
     *  customer_gstin?, customer_state_code?, customer_address?,
     *  lines: [{batch_id, qty_units, mrp_paise, batch_version, discount_bp?}]}
     *
     * 201 {bill, batches} | 200 same, for a retry of a created bill
     * 409 price_changed | 422 insufficient_stock / batch_unavailable / validation
     */
    public function store(Request $request): JsonResponse
    {
        $input = $request->all();
        if (is_string($input['customer_gstin'] ?? null)) {
            $input['customer_gstin'] = strtoupper(trim($input['customer_gstin'])) ?: null;
        }
        $request->replace($input);

        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'device_id' => ['nullable', 'string', 'max:64'],
            'payment_mode' => ['required', Rule::in(Bill::PAYMENT_MODES)],
            // A credit (udhaar) sale has to say who owes the money.
            'customer_name' => ['nullable', 'string', 'max:100', 'required_if:payment_mode,credit'],
            'customer_phone' => ['nullable', 'string', 'regex:/^[0-9+\-\s()]{6,20}$/'],
            'customer_gstin' => ['nullable', 'string', new Gstin],
            'customer_state_code' => ['nullable', 'string', Rule::in(GstStates::codes())],
            'customer_address' => ['nullable', 'string', 'max:500'],
            'lines' => ['required', 'array', 'min:1', 'max:200'],
            'lines.*.batch_id' => ['required', 'uuid'],
            'lines.*.qty_units' => ['required', 'integer', 'min:1', 'max:100000'],
            'lines.*.mrp_paise' => ['required', 'integer', 'min:0'],
            'lines.*.batch_version' => ['required', 'integer', 'min:0'],
            'lines.*.discount_bp' => ['nullable', 'integer', 'min:0', 'max:10000'],
        ]);
        $data['id'] = strtolower($data['id']);

        $user = $request->user();
        [$bill, $created, $stock] = $this->billing->create($this->shops->forUser($user), $user, $data);

        return response()->json([
            'bill' => $bill->toApi(),
            'batches' => $stock,
            'replayed' => ! $created,
        ], $created ? 201 : 200);
    }

    /** GET /bills/{id} */
    public function show(Request $request, string $bill): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());

        return response()->json(['bill' => $this->find($shop, $bill)->toApi()]);
    }

    /**
     * POST /bills/{id}/cancel {reason?, device_id?}
     * Puts the stock back; the invoice number stays used.
     */
    public function cancel(Request $request, string $bill): JsonResponse
    {
        $data = $request->validate([
            'reason' => ['nullable', 'string', 'max:255'],
            'device_id' => ['nullable', 'string', 'max:64'],
        ]);
        $user = $request->user();
        $shop = $this->shops->forUser($user);

        [$model, $stock] = $this->billing->cancel($shop, $user, $this->find($shop, $bill),
            $data['reason'] ?? null, $data['device_id'] ?? null);

        return response()->json(['bill' => $model->toApi(), 'batches' => $stock]);
    }

    /** The shop's bill, or 404 (another shop's bill is "not found" too). */
    private function find(Shop $shop, string $id): Bill
    {
        $bill = Str::isUuid($id)
            ? Bill::with('items')->where('shop_id', $shop->id)->find(strtolower($id))
            : null;
        abort_if($bill === null, 404, 'Bill not found.');

        return $bill;
    }
}
