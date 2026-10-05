<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\ApiRefused;
use App\Http\Controllers\Controller;
use App\Models\Bill;
use App\Models\Party;
use App\Models\PartyPayment;
use App\Models\Purchase;
use App\Models\Shop;
use App\Services\BillingService;
use App\Services\PartyLedger;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Payments in (received from a party) and out (paid to a party), with an
 * optional link to the credit bill or purchase they settle. A payment is
 * never deleted or edited; a mistake is cancelled and re-entered.
 */
class PartyPaymentController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly PartyLedger $ledger,
    ) {}

    /** GET /payments?party_id=&direction=&from=&to=&page=&per_page= (newest first) */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'party_id' => ['nullable', 'uuid'],
            'direction' => ['nullable', Rule::in(PartyPayment::DIRECTIONS)],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $page = PartyPayment::where('shop_id', $shop->id)
            ->when($data['party_id'] ?? null, fn ($q, $p) => $q->where('party_id', strtolower($p)))
            ->when($data['direction'] ?? null, fn ($q, $d) => $q->where('direction', $d))
            ->when($data['from'] ?? null, fn ($q, $d) => $q->where('payment_date', '>=', $d))
            ->when($data['to'] ?? null, fn ($q, $d) => $q->where('payment_date', '<=', $d))
            ->orderByDesc('payment_date')->orderByDesc('created_at')
            ->paginate((int) ($data['per_page'] ?? 30));

        return response()->json([
            'data' => array_map(fn (PartyPayment $p) => $p->toApi(), $page->items()),
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'per_page' => $page->perPage(),
                'total' => $page->total(),
            ],
        ]);
    }

    /**
     * POST /payments
     * {id, device_id?, party_id, direction: in|out, amount_paise, mode: cash|upi|card|bank|cheque,
     *  reference?, payment_date?, notes?, bill_id? (in only), purchase_id? (out only)}
     * 201 {payment, balance_paise} | 200 + replayed for a retry
     * 422 over_allocated / validation; 404 party, bill or purchase of another shop
     */
    public function store(Request $request): JsonResponse
    {
        $today = now(BillingService::TIMEZONE)->toDateString();
        $data = $request->validate([
            'id' => ['required', 'uuid'],
            'device_id' => ['nullable', 'string', 'max:64'],
            'party_id' => ['required', 'uuid'],
            'direction' => ['required', Rule::in(PartyPayment::DIRECTIONS)],
            'amount_paise' => ['required', 'integer', 'min:1', 'max:100000000000'],
            'mode' => ['required', Rule::in(PartyPayment::MODES)],
            'reference' => ['nullable', 'string', 'max:64'],
            'payment_date' => ['nullable', 'date_format:Y-m-d', 'before_or_equal:'.$today],
            'notes' => ['nullable', 'string', 'max:500'],
            'bill_id' => ['nullable', 'uuid', 'prohibits:purchase_id', 'prohibited_if:direction,out'],
            'purchase_id' => ['nullable', 'uuid', 'prohibited_if:direction,in'],
        ]);
        $user = $request->user();
        $shop = $this->shops->forUser($user);
        $party = PartyController::findFor($shop, $data['party_id']);
        $id = strtolower($data['id']);

        [$payment, $created] = DB::transaction(function () use ($shop, $user, $party, $data, $id, $today) {
            Shop::whereKey($shop->id)->lockForUpdate()->first();
            $existing = PartyPayment::find($id);
            if ($existing) {
                abort_if((int) $existing->shop_id !== (int) $shop->id, 422, 'This payment id is already in use.');

                return [$existing, false];
            }

            if (! empty($data['bill_id'])) {
                $bill = Bill::where('shop_id', $shop->id)->where('party_id', $party->id)->find(strtolower($data['bill_id']));
                abort_if($bill === null, 404, 'Bill not found for this customer.');
                if ($bill->isCancelled() || $bill->payment_mode !== 'credit') {
                    throw new ApiRefused(422, 'not_payable', 'Only a credit bill that is not cancelled can be settled.');
                }
                $this->checkAllocation($this->ledger->billOutstanding($bill), (int) $data['amount_paise']);
            }
            if (! empty($data['purchase_id'])) {
                $purchase = Purchase::where('shop_id', $shop->id)->where('party_id', $party->id)->find(strtolower($data['purchase_id']));
                abort_if($purchase === null, 404, 'Purchase not found for this supplier.');
                if ($purchase->isCancelled()) {
                    throw new ApiRefused(422, 'not_payable', 'This purchase is cancelled.');
                }
                $this->checkAllocation($this->ledger->purchaseOutstanding($purchase), (int) $data['amount_paise']);
            }

            $payment = new PartyPayment;
            $payment->id = $id;
            $payment->forceFill([
                'shop_id' => $shop->id,
                'party_id' => $party->id,
                'user_id' => $user->id,
                'device_id' => $data['device_id'] ?? null,
                'direction' => $data['direction'],
                'amount_paise' => (int) $data['amount_paise'],
                'mode' => $data['mode'],
                'reference' => $data['reference'] ?? null,
                'payment_date' => $data['payment_date'] ?? $today,
                'notes' => $data['notes'] ?? null,
                'bill_id' => isset($data['bill_id']) ? strtolower($data['bill_id']) : null,
                'purchase_id' => isset($data['purchase_id']) ? strtolower($data['purchase_id']) : null,
                'status' => PartyPayment::STATUS_ACTIVE,
            ])->save();

            return [$payment->fresh(), true];
        });

        return response()->json([
            'payment' => $payment->toApi(),
            'balance_paise' => $this->ledger->balance($party),
            'replayed' => ! $created,
        ], $created ? 201 : 200);
    }

    /** POST /payments/{id}/cancel {reason?}: takes it out of the ledger; cancelling again changes nothing. */
    public function cancel(Request $request, string $payment): JsonResponse
    {
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:255']]);
        $shop = $this->shops->forUser($request->user());
        $model = Str::isUuid($payment) ? PartyPayment::where('shop_id', $shop->id)->find(strtolower($payment)) : null;
        abort_if($model === null, 404, 'Payment not found.');

        if (! $model->isCancelled()) {
            $model->forceFill([
                'status' => PartyPayment::STATUS_CANCELLED,
                'cancelled_at' => now(),
                'cancel_reason' => $data['reason'] ?? null,
            ])->save();
        }
        $party = Party::withTrashed()->find($model->party_id);

        return response()->json(['payment' => $model->toApi(), 'balance_paise' => $this->ledger->balance($party)]);
    }

    private function checkAllocation(int $outstanding, int $amount): void
    {
        if ($amount > $outstanding) {
            throw new ApiRefused(422, 'over_allocated',
                'The amount is more than what is still due on it ('.number_format($outstanding / 100, 2).').',
                ['outstanding_paise' => max(0, $outstanding)]);
        }
    }
}
