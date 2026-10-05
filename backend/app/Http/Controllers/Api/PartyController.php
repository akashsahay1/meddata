<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiRefused;
use App\Http\Controllers\Controller;
use App\Models\Bill;
use App\Models\Party;
use App\Models\Purchase;
use App\Models\Shop;
use App\Rules\Gstin;
use App\Services\PartyLedger;
use App\Services\ShopService;
use App\Support\GstStates;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * The shop's customers and suppliers (one table), their balances and
 * ledgers. Online-only. Balance sign: + the party owes the shop, - the shop
 * owes the party.
 */
class PartyController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly PartyLedger $ledger,
    ) {}

    /**
     * GET /parties?type=customer|supplier&q=&page=&per_page=
     * By name. `customer` also lists 'both' parties, as does `supplier`.
     */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => ['nullable', Rule::in(['customer', 'supplier'])],
            'q' => ['nullable', 'string', 'max:100'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:200'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $search = trim((string) ($data['q'] ?? ''));

        $page = Party::where('shop_id', $shop->id)
            ->when($data['type'] ?? null, fn ($q, $t) => $q->whereIn('type', [$t, 'both']))
            ->when($search !== '', function ($q) use ($search) {
                $like = '%'.addcslashes(Party::normalizeName($search), '%_\\').'%';
                $raw = '%'.addcslashes($search, '%_\\').'%';
                $q->where(fn ($w) => $w->where('name_norm', 'like', $like)
                    ->orWhere('phone', 'like', $raw)
                    ->orWhere('gstin', 'like', strtoupper($raw)));
            })
            ->orderBy('name_norm')
            ->paginate((int) ($data['per_page'] ?? 50));

        $balances = $this->ledger->balances($shop->id, array_map(fn (Party $p) => $p->id, $page->items()));

        return response()->json([
            'data' => array_map(fn (Party $p) => $p->toApi($balances[$p->id] ?? 0), $page->items()),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    /**
     * POST /parties {id?, type, name, phone?, gstin?, state_code?, address?,
     * opening_balance_paise?, notes?}
     * 201 {party} | 200 {party, replayed} for a retry with the same id.
     */
    public function store(Request $request): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());
        $data = $this->validated($request, $shop, null);

        $id = strtolower($data['id'] ?? (string) Str::uuid());
        $existing = Party::withTrashed()->find($id);
        if ($existing) {
            abort_if((int) $existing->shop_id !== (int) $shop->id, 422, 'This party id is already in use.');

            return response()->json(['party' => $existing->toApi($this->ledger->balance($existing)), 'replayed' => true]);
        }

        $party = new Party;
        $party->id = $id;
        $party->forceFill(array_diff_key($data, ['id' => true]) + [
            'shop_id' => $shop->id,
            'name_norm' => Party::normalizeName($data['name']),
            'opening_balance_paise' => (int) ($data['opening_balance_paise'] ?? 0),
            'created_by' => $request->user()->id,
        ])->save();

        return response()->json(['party' => $party->fresh()->toApi($this->ledger->balance($party))], 201);
    }

    /** GET /parties/{id}: the party, its balance and its unsettled credit bills / purchases. */
    public function show(Request $request, string $party): JsonResponse
    {
        $model = $this->find($this->shops->forUser($request->user()), $party);

        return response()->json([
            'party' => $model->toApi($this->ledger->balance($model)),
            'open_documents' => $this->ledger->openDocuments($model),
        ]);
    }

    /** PATCH /parties/{id} (only the fields given). */
    public function update(Request $request, string $party): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());
        $model = $this->find($shop, $party);
        $data = $this->validated($request, $shop, $model);
        unset($data['id']);

        if (isset($data['type'])) {
            $this->checkType($model, $data['type']);
        }
        if (isset($data['name'])) {
            $data['name_norm'] = Party::normalizeName($data['name']);
        }
        $model->forceFill($data)->save();

        return response()->json(['party' => $model->fresh()->toApi($this->ledger->balance($model))]);
    }

    /**
     * DELETE /parties/{id}: hidden from lists (its documents keep their
     * copy of the name). Refused (422 balance_not_zero) while money is due.
     */
    public function destroy(Request $request, string $party): JsonResponse
    {
        $model = $this->find($this->shops->forUser($request->user()), $party);
        $balance = $this->ledger->balance($model);
        if ($balance !== 0) {
            throw new ApiRefused(422, 'balance_not_zero',
                'This party still has a balance. Settle it before deleting the party.', ['balance_paise' => $balance]);
        }
        $model->delete();

        return response()->json(['deleted' => true]);
    }

    /** GET /parties/{id}/ledger?from=Y-m-d&to=Y-m-d */
    public function ledger(Request $request, string $party): JsonResponse
    {
        $data = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $model = $this->find($shop, $party);

        return response()->json([
            'party' => $model->toApi($this->ledger->balance($model)),
            'from' => $data['from'] ?? null,
            'to' => $data['to'] ?? null,
            'seller' => $shop->invoiceDetails(),
        ] + $this->ledger->ledger($model, $data['from'] ?? null, $data['to'] ?? null));
    }

    // ---------------------------------------------------------------------

    /** The shop's (not deleted) party, or 404. */
    public static function findFor(Shop $shop, string $id): Party
    {
        $party = Str::isUuid($id) ? Party::where('shop_id', $shop->id)->find(strtolower($id)) : null;
        abort_if($party === null, 404, 'Party not found.');

        return $party;
    }

    private function find(Shop $shop, string $id): Party
    {
        return self::findFor($shop, $id);
    }

    private function validated(Request $request, Shop $shop, ?Party $current): array
    {
        $input = $request->all();
        if (is_string($input['gstin'] ?? null)) {
            $input['gstin'] = strtoupper(preg_replace('/\s+/', '', $input['gstin'])) ?: null;
        }
        foreach (['phone', 'address', 'notes'] as $key) {
            if (is_string($input[$key] ?? null) && trim($input[$key]) === '') {
                $input[$key] = null;
            }
        }
        if (is_int($input['state_code'] ?? null) || ctype_digit((string) ($input['state_code'] ?? 'x'))) {
            $input['state_code'] = str_pad((string) $input['state_code'], 2, '0', STR_PAD_LEFT);
        }
        $request->replace($input);

        $sometimes = $current ? 'sometimes' : 'nullable';
        $data = $request->validate([
            'id' => [$current ? 'prohibited' : 'nullable', 'uuid'],
            'type' => [$current ? 'sometimes' : 'required', Rule::in(Party::TYPES)],
            'name' => [$current ? 'sometimes' : 'required', 'string', 'min:1', 'max:100'],
            'phone' => [$sometimes, 'nullable', 'string', 'regex:/^[0-9+\-\s()]{6,20}$/'],
            'gstin' => [$sometimes, 'nullable', 'string', new Gstin],
            'state_code' => [$sometimes, 'nullable', 'string', Rule::in(GstStates::codes())],
            'address' => [$sometimes, 'nullable', 'string', 'max:500'],
            'opening_balance_paise' => [$sometimes, 'nullable', 'integer', 'min:-100000000000', 'max:100000000000'],
            'notes' => [$sometimes, 'nullable', 'string', 'max:2000'],
        ]);
        if (array_key_exists('name', $data)) {
            $data['name'] = trim($data['name']);
        }

        // The state follows the GSTIN, and must match it when both are given.
        $gstin = array_key_exists('gstin', $data) ? $data['gstin'] : $current?->gstin;
        $state = array_key_exists('state_code', $data) ? $data['state_code'] : $current?->state_code;
        if ($gstin) {
            $fromGstin = substr($gstin, 0, 2);
            if (! $state || (array_key_exists('gstin', $data) && ! array_key_exists('state_code', $data))) {
                $data['state_code'] = $fromGstin;
            } elseif ($state !== $fromGstin) {
                throw ValidationException::withMessages([
                    'state_code' => 'The state must match the GSTIN (its first two digits are '.$fromGstin.').',
                ]);
            }
            $taken = Party::where('shop_id', $shop->id)->where('gstin', $gstin)
                ->when($current, fn ($q) => $q->whereKeyNot($current->id))
                ->when(! $current && isset($data['id']), fn ($q) => $q->whereKeyNot(strtolower($data['id'])))
                ->exists();
            if ($taken) {
                throw ValidationException::withMessages(['gstin' => 'Another party already has this GSTIN.']);
            }
        }

        return $data;
    }

    /** A party with bills must stay a customer; one with purchases a supplier. */
    private function checkType(Party $party, string $type): void
    {
        $customer = in_array($type, ['customer', 'both'], true);
        $supplier = in_array($type, ['supplier', 'both'], true);
        if (! $customer && Bill::where('party_id', $party->id)->exists()) {
            throw ValidationException::withMessages(['type' => 'This party has bills, so it must stay a customer (or both).']);
        }
        if (! $supplier && (Purchase::where('party_id', $party->id)->exists()
            || DB::table('purchase_returns')->where('party_id', $party->id)->exists())) {
            throw ValidationException::withMessages(['type' => 'This party has purchases, so it must stay a supplier (or both).']);
        }
    }
}
