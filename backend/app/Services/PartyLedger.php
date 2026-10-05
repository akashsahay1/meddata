<?php

namespace App\Services;

use App\Models\Bill;
use App\Models\Party;
use App\Models\PartyPayment;
use App\Models\Purchase;
use Illuminate\Support\Facades\DB;

/**
 * A party's account, worked out from the documents (nothing is stored
 * twice). Sign: debit (+) = the party owes the shop more, credit (-) = less.
 *
 *   opening balance                  as entered (+ receivable, - payable)
 *   credit sale bill (not cancelled)  + total     (cash/UPI/card bills are paid at once)
 *   payment received (in)             - amount
 *   payment made (out)                + amount
 *   purchase (not cancelled)          - total     (owed to the supplier)
 *   sale return adjusted on account   - total     (credit note, refund_mode 'credit')
 *   purchase return                   + total     (debit note)
 *
 * Cancelled bills, purchases and payments are left out.
 */
class PartyLedger
{
    /**
     * Ledger lines in date order with a running balance. With a date range
     * the first line is the balance brought forward.
     *
     * @return array{opening_paise: int, closing_paise: int, debit_paise: int, credit_paise: int, entries: list<array<string, mixed>>}
     */
    public function ledger(Party $party, ?string $from = null, ?string $to = null): array
    {
        $all = $this->entries($party);
        $balance = (int) $party->opening_balance_paise;
        $entries = [];
        $debit = $credit = 0;
        foreach ($all as $e) {
            if ($from !== null && $e['date'] < $from) {
                $balance += $e['debit_paise'] - $e['credit_paise'];

                continue;
            }
            if ($to !== null && $e['date'] > $to) {
                continue;
            }
            $entries[] = $e;
        }
        $opening = $balance;
        foreach ($entries as &$e) {
            $balance += $e['debit_paise'] - $e['credit_paise'];
            $debit += $e['debit_paise'];
            $credit += $e['credit_paise'];
            $e['balance_paise'] = $balance;
        }
        unset($e);

        return [
            'opening_paise' => $opening,
            'closing_paise' => $balance,
            'debit_paise' => $debit,
            'credit_paise' => $credit,
            'entries' => $entries,
        ];
    }

    /** The party's balance now. */
    public function balance(Party $party): int
    {
        return $this->balances($party->shop_id, [$party->id])[$party->id] ?? (int) $party->opening_balance_paise;
    }

    /**
     * Current balances of many parties in a few grouped queries.
     *
     * @param  array<int, string>  $partyIds
     * @return array<string, int>
     */
    public function balances(int $shopId, array $partyIds): array
    {
        if ($partyIds === []) {
            return [];
        }
        $out = Party::withTrashed()->where('shop_id', $shopId)->whereIn('id', $partyIds)
            ->pluck('opening_balance_paise', 'id')->map(fn ($v) => (int) $v)->all();

        $add = function (string $table, string $sign, callable $where, string $amount = 'total_paise') use (&$out, $shopId, $partyIds) {
            $q = DB::table($table)->where('shop_id', $shopId)->whereIn('party_id', $partyIds);
            $where($q);
            foreach ($q->groupBy('party_id')->selectRaw("party_id, SUM($amount) AS s")->get() as $row) {
                $out[$row->party_id] = ($out[$row->party_id] ?? 0) + ($sign === '+' ? 1 : -1) * (int) $row->s;
            }
        };
        $add('bills', '+', fn ($q) => $q->where('payment_mode', 'credit')->where('status', Bill::STATUS_FINAL));
        $add('party_payments', '-', fn ($q) => $q->where('direction', 'in')->where('status', PartyPayment::STATUS_ACTIVE), 'amount_paise');
        $add('party_payments', '+', fn ($q) => $q->where('direction', 'out')->where('status', PartyPayment::STATUS_ACTIVE), 'amount_paise');
        $add('purchases', '-', fn ($q) => $q->where('status', Purchase::STATUS_FINAL));
        $add('sale_returns', '-', fn ($q) => $q->where('refund_mode', 'credit'));
        $add('purchase_returns', '+', fn ($q) => $q);

        return $out;
    }

    /**
     * Credit bills and purchases of the party with money still to settle
     * (for allocating a payment), oldest first.
     *
     * @return list<array{type: string, id: string, number: string, date: string, total_paise: int, outstanding_paise: int}>
     */
    public function openDocuments(Party $party): array
    {
        $out = [];
        $bills = Bill::where('shop_id', $party->shop_id)->where('party_id', $party->id)
            ->where('payment_mode', 'credit')->where('status', Bill::STATUS_FINAL)
            ->orderBy('bill_date')->orderBy('seq')->get();
        foreach ($bills as $bill) {
            $left = $this->billOutstanding($bill);
            if ($left > 0) {
                $out[] = ['type' => 'bill', 'id' => $bill->id, 'number' => $bill->invoice_no, 'date' => $bill->billDate(),
                    'total_paise' => (int) $bill->total_paise, 'outstanding_paise' => $left];
            }
        }
        $purchases = Purchase::where('shop_id', $party->shop_id)->where('party_id', $party->id)
            ->where('status', Purchase::STATUS_FINAL)->orderBy('invoice_date')->orderBy('created_at')->get();
        foreach ($purchases as $purchase) {
            $left = $this->purchaseOutstanding($purchase);
            if ($left > 0) {
                $out[] = ['type' => 'purchase', 'id' => $purchase->id, 'number' => $purchase->supplier_invoice_no,
                    'date' => Purchase::day($purchase->invoice_date), 'total_paise' => (int) $purchase->total_paise, 'outstanding_paise' => $left];
            }
        }

        return $out;
    }

    /** A credit bill's total less payments against it and credit notes adjusted on account. */
    public function billOutstanding(Bill $bill): int
    {
        $paid = (int) DB::table('party_payments')->where('bill_id', $bill->id)
            ->where('direction', 'in')->where('status', PartyPayment::STATUS_ACTIVE)->sum('amount_paise');
        $returned = (int) DB::table('sale_returns')->where('bill_id', $bill->id)
            ->where('refund_mode', 'credit')->sum('total_paise');

        return (int) $bill->total_paise - $paid - $returned;
    }

    /** A purchase's total less payments against it and debit notes against it. */
    public function purchaseOutstanding(Purchase $purchase): int
    {
        $paid = (int) DB::table('party_payments')->where('purchase_id', $purchase->id)
            ->where('direction', 'out')->where('status', PartyPayment::STATUS_ACTIVE)->sum('amount_paise');
        $returned = (int) DB::table('purchase_returns')->where('purchase_id', $purchase->id)->sum('total_paise');

        return (int) $purchase->total_paise - $paid - $returned;
    }

    /** @return list<array<string, mixed>> every ledger line of the party, oldest first */
    private function entries(Party $party): array
    {
        $shop = $party->shop_id;
        $id = $party->id;
        $rows = [];
        $line = fn (string $type, string $docId, ?string $no, string $date, int $debit, int $credit, string $text, string $at) => [
            'type' => $type, 'id' => $docId, 'number' => $no, 'date' => substr($date, 0, 10),
            'description' => $text, 'debit_paise' => $debit, 'credit_paise' => $credit, '_at' => $at,
        ];

        foreach (DB::table('bills')->where('shop_id', $shop)->where('party_id', $id)
            ->where('payment_mode', 'credit')->where('status', Bill::STATUS_FINAL)->get() as $b) {
            $rows[] = $line('sale', $b->id, $b->invoice_no, (string) $b->bill_date, (int) $b->total_paise, 0,
                'Credit sale', (string) $b->created_at);
        }
        foreach (DB::table('party_payments')->where('shop_id', $shop)->where('party_id', $id)
            ->where('status', PartyPayment::STATUS_ACTIVE)->get() as $p) {
            $in = $p->direction === 'in';
            $text = ($in ? 'Payment received' : 'Payment made').' · '.strtoupper($p->mode)
                .($p->reference ? ' '.$p->reference : '');
            $rows[] = $line($in ? 'payment_in' : 'payment_out', $p->id, $p->reference, (string) $p->payment_date,
                $in ? 0 : (int) $p->amount_paise, $in ? (int) $p->amount_paise : 0, $text, (string) $p->created_at);
        }
        foreach (DB::table('purchases')->where('shop_id', $shop)->where('party_id', $id)
            ->where('status', Purchase::STATUS_FINAL)->get() as $p) {
            $rows[] = $line('purchase', $p->id, $p->supplier_invoice_no, (string) $p->invoice_date, 0, (int) $p->total_paise,
                'Purchase', (string) $p->created_at);
        }
        foreach (DB::table('sale_returns')->where('shop_id', $shop)->where('party_id', $id)
            ->where('refund_mode', 'credit')->get() as $r) {
            $rows[] = $line('sale_return', $r->id, $r->note_no, (string) $r->return_date, 0, (int) $r->total_paise,
                'Sale return (credit note)', (string) $r->created_at);
        }
        foreach (DB::table('purchase_returns')->where('shop_id', $shop)->where('party_id', $id)->get() as $r) {
            $rows[] = $line('purchase_return', $r->id, $r->note_no, (string) $r->return_date, (int) $r->total_paise, 0,
                'Purchase return (debit note)', (string) $r->created_at);
        }

        // Same day and second: bills and purchases first, then payments, then returns.
        $order = ['sale' => 0, 'purchase' => 0, 'payment_in' => 1, 'payment_out' => 1, 'sale_return' => 2, 'purchase_return' => 2];
        usort($rows, fn ($a, $b) => [$a['date'], $a['_at'], $order[$a['type']], $a['id']]
            <=> [$b['date'], $b['_at'], $order[$b['type']], $b['id']]);

        return array_map(function ($r) {
            unset($r['_at']);

            return $r;
        }, $rows);
    }
}
