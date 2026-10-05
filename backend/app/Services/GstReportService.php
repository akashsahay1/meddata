<?php

namespace App\Services;

use App\Models\Bill;
use App\Models\Purchase;
use App\Models\PurchaseReturn;
use App\Models\SaleReturn;
use App\Models\Shop;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * GSTR-1 and GSTR-3B style summaries of a month, worked out from the
 * shop's bills, credit notes, purchases and debit notes. They are drafts
 * for the shop's CA to review before filing, not a filing; every response
 * says so.
 *
 * Conventions (documented for the CA):
 * - Dates: bill date, credit/debit note date, supplier invoice date (ITC).
 * - Cancelled bills and purchases are left out (their numbers still count
 *   in the document summary).
 * - Bills to a GSTIN are B2B; to others, inter-state invoices above
 *   Rs 1,00,000 are B2C large, everything else B2C small.
 * - 0% GST lines are reported as nil rated, not in B2B / B2C.
 * - Credit notes to registered customers are CDNR; against B2C large
 *   invoices CDNUR; against B2C small invoices they are netted in B2C small
 *   (and in the HSN summary), as the portal expects.
 * - Debit notes to suppliers (purchase returns) reduce ITC in GSTR-3B; they
 *   are not part of GSTR-1.
 */
class GstReportService
{
    /** B2C large: inter-state invoice value above Rs 1,00,000 (since Aug 2024). */
    public const B2CL_LIMIT_PAISE = 10_000_000;

    public const DISCLAIMER = 'Prepared by Meddata from your bills and purchases for review by your CA. '
        .'It is not filed with the GST portal; check it before filing.';

    private const TAX = ['taxable_paise', 'igst_paise', 'cgst_paise', 'sgst_paise'];

    /** @return array{0: string, 1: string} first and last day of "Y-m" */
    public static function monthRange(string $month): array
    {
        $start = Carbon::createFromFormat('!Y-m', $month);

        return [$start->toDateString(), $start->copy()->endOfMonth()->toDateString()];
    }

    public function gstr1(Shop $shop, string $month): array
    {
        [$from, $to] = self::monthRange($month);
        $bills = Bill::with('items')->where('shop_id', $shop->id)
            ->whereBetween('bill_date', [$from, $to])->orderBy('fy')->orderBy('seq')->get();
        $final = $bills->where('status', Bill::STATUS_FINAL);
        $notes = SaleReturn::with(['items', 'bill'])->where('shop_id', $shop->id)
            ->whereBetween('return_date', [$from, $to])->orderBy('fy')->orderBy('seq')->get();

        $b2b = [];
        $b2cl = [];
        $b2cs = [];
        $nil = [];
        $hsn = [];
        foreach ($final as $bill) {
            $kind = $this->kind($bill);
            $rates = $this->rates($bill->items, 1);
            foreach ($bill->items as $item) {
                $this->addHsn($hsn, $kind === 'b2b' ? 'b2b' : 'b2c', $item, (int) $item->qty_units, 1);
                if ((int) $item->gst_rate_bp === 0) {
                    $this->addNil($nil, $bill, $item, 1);
                }
            }
            if ($rates === []) {
                continue;
            }
            $doc = $this->invoiceRow($bill, $rates);
            if ($kind === 'b2b') {
                $b2b[$bill->customer_gstin] ??= ['gstin' => $bill->customer_gstin, 'name' => $bill->customer_name,
                    'invoices' => [], 'invoice_count' => 0, 'invoice_value_paise' => 0] + $this->zero();
                $b2b[$bill->customer_gstin]['invoices'][] = $doc;
                $b2b[$bill->customer_gstin]['invoice_count']++;
                $b2b[$bill->customer_gstin]['invoice_value_paise'] += (int) $bill->total_paise;
                $this->add($b2b[$bill->customer_gstin], $rates);
            } elseif ($kind === 'b2cl') {
                $b2cl[] = $doc;
            } else {
                $this->addB2cs($b2cs, $bill, $rates, 1);
            }
        }

        $cdnr = [];
        $cdnur = [];
        foreach ($notes as $note) {
            $bill = $note->bill;
            $kind = $bill ? $this->kind($bill) : 'b2cs';
            $rates = $this->rates($note->items, 1);
            foreach ($note->items as $item) {
                $this->addHsn($hsn, $kind === 'b2b' ? 'b2b' : 'b2c', $item, (int) $item->qty_units, -1);
                if ((int) $item->gst_rate_bp === 0 && $bill) {
                    $this->addNil($nil, $bill, $item, -1);
                }
            }
            if ($rates === []) {
                continue;
            }
            $row = [
                'note_no' => $note->note_no,
                'note_date' => substr((string) $note->return_date, 0, 10),
                'note_type' => 'C',
                'note_value_paise' => (int) $note->total_paise,
                'place_of_supply' => $note->place_of_supply,
                'invoice_no' => $bill?->invoice_no,
                'invoice_date' => $bill?->billDate(),
                'gstin' => $note->customer_gstin,
                'name' => $note->customer_name,
                'rates' => $rates,
            ];
            if ($kind === 'b2b') {
                $cdnr[] = $row;
            } elseif ($kind === 'b2cl') {
                $cdnur[] = $row + ['type' => 'B2CL'];
            } elseif ($bill) {
                $this->addB2cs($b2cs, $bill, $rates, -1);
            }
        }

        ksort($b2cs);
        ksort($hsn);

        return [
            'return' => 'GSTR-1',
            'month' => $month,
            'from' => $from,
            'to' => $to,
            'gstin' => $shop->gstin,
            'registered' => $shop->gstin !== null,
            'legal_name' => $shop->legal_name ?: $shop->name,
            'disclaimer' => self::DISCLAIMER,
            'b2b' => array_values($b2b),
            'b2cl' => $b2cl,
            'b2cs' => array_values($b2cs),
            'cdnr' => $cdnr,
            'cdnur' => $cdnur,
            'nil_rated' => array_values($nil),
            'hsn' => [
                'b2b' => array_values(array_filter($hsn, fn ($r) => $r['section'] === 'b2b')),
                'b2c' => array_values(array_filter($hsn, fn ($r) => $r['section'] === 'b2c')),
            ],
            'documents' => [
                $this->documentRow('Invoices for outward supply', $bills->map(fn (Bill $b) => [$b->invoice_no, $b->fy, $b->seq, $b->isCancelled()])),
                $this->documentRow('Credit notes', $notes->map(fn (SaleReturn $n) => [$n->note_no, $n->fy, $n->seq, false])),
            ],
            'summary' => [
                'bills' => $this->sumDocs($final),
                'credit_notes' => $this->sumDocs($notes),
                'net' => $this->net($this->sumDocs($final), $this->sumDocs($notes)),
            ],
        ];
    }

    public function gstr3b(Shop $shop, string $month): array
    {
        [$from, $to] = self::monthRange($month);
        $bills = Bill::with('items')->where('shop_id', $shop->id)->where('status', Bill::STATUS_FINAL)
            ->whereBetween('bill_date', [$from, $to])->get();
        $notes = SaleReturn::with(['items', 'bill'])->where('shop_id', $shop->id)
            ->whereBetween('return_date', [$from, $to])->get();
        $purchases = Purchase::where('shop_id', $shop->id)->where('status', Purchase::STATUS_FINAL)
            ->whereBetween('invoice_date', [$from, $to])->get();
        $debitNotes = PurchaseReturn::where('shop_id', $shop->id)
            ->whereBetween('return_date', [$from, $to])->get();

        $taxable = $this->zero();
        $nil = ['taxable_paise' => 0];
        $unregistered = [];
        foreach ([[$bills, 1], [$notes, -1]] as [$docs, $sign]) {
            foreach ($docs as $doc) {
                $bill = $doc instanceof Bill ? $doc : $doc->bill;
                foreach ($doc->items as $item) {
                    if ((int) $item->gst_rate_bp === 0) {
                        $nil['taxable_paise'] += $sign * (int) $item->taxable_paise;

                        continue;
                    }
                    foreach (self::TAX as $k) {
                        $taxable[$k] += $sign * (int) $item->{$k};
                    }
                    if ($bill && $bill->is_inter_state && $bill->customer_gstin === null) {
                        $pos = $bill->place_of_supply;
                        $unregistered[$pos] ??= ['place_of_supply' => $pos, 'taxable_paise' => 0, 'igst_paise' => 0];
                        $unregistered[$pos]['taxable_paise'] += $sign * (int) $item->taxable_paise;
                        $unregistered[$pos]['igst_paise'] += $sign * (int) $item->igst_paise;
                    }
                }
            }
        }
        ksort($unregistered);

        $itc = $this->zero();
        foreach ($purchases as $p) {
            foreach (self::TAX as $k) {
                $itc[$k] += (int) $p->{$k};
            }
        }
        $reversed = $this->zero();
        foreach ($debitNotes as $d) {
            foreach (self::TAX as $k) {
                $reversed[$k] += (int) $d->{$k};
            }
        }
        $netItc = [];
        foreach (['igst_paise', 'cgst_paise', 'sgst_paise'] as $k) {
            $netItc[$k] = $itc[$k] - $reversed[$k];
        }

        return [
            'return' => 'GSTR-3B',
            'month' => $month,
            'from' => $from,
            'to' => $to,
            'gstin' => $shop->gstin,
            'registered' => $shop->gstin !== null,
            'legal_name' => $shop->legal_name ?: $shop->name,
            'disclaimer' => self::DISCLAIMER,
            'outward_taxable' => $taxable,
            'outward_nil_rated' => $nil,
            'inter_state_unregistered' => array_values($unregistered),
            'itc' => [
                'available' => $itc + ['purchase_count' => $purchases->count()],
                'reversed' => $reversed + ['debit_note_count' => $debitNotes->count()],
                'net' => $netItc,
            ],
            'payment' => self::setOff(
                ['igst_paise' => $taxable['igst_paise'], 'cgst_paise' => $taxable['cgst_paise'], 'sgst_paise' => $taxable['sgst_paise']],
                $netItc,
            ),
        ];
    }

    /**
     * Uses input tax credit against the output tax in the order the law
     * sets: IGST credit first (IGST, then CGST, then SGST), then CGST credit
     * (CGST, then IGST), then SGST credit (SGST, then IGST). CGST credit is
     * never used for SGST, nor SGST for CGST.
     *
     * @param  array{igst_paise: int, cgst_paise: int, sgst_paise: int}  $liability
     * @param  array{igst_paise: int, cgst_paise: int, sgst_paise: int}  $credit
     */
    public static function setOff(array $liability, array $credit): array
    {
        $due = array_map(fn ($v) => max(0, (int) $v), $liability);
        $left = array_map(fn ($v) => max(0, (int) $v), $credit);
        $used = ['igst_paise' => 0, 'cgst_paise' => 0, 'sgst_paise' => 0];
        $use = function (string $from, string $against) use (&$due, &$left, &$used) {
            $x = min($left[$from], $due[$against]);
            $left[$from] -= $x;
            $due[$against] -= $x;
            $used[$from] += $x;
        };
        foreach ([['igst_paise', 'igst_paise'], ['igst_paise', 'cgst_paise'], ['igst_paise', 'sgst_paise'],
            ['cgst_paise', 'cgst_paise'], ['cgst_paise', 'igst_paise'],
            ['sgst_paise', 'sgst_paise'], ['sgst_paise', 'igst_paise']] as [$from, $against]) {
            $use($from, $against);
        }

        return [
            'tax_payable' => $liability,
            'itc_used' => $used,
            'cash_payable' => $due + ['total_paise' => array_sum($due)],
            'itc_carried_forward' => $left + ['total_paise' => array_sum($left)],
        ];
    }

    // ---------------------------------------------------------------------

    private function kind(Bill $bill): string
    {
        if ($bill->customer_gstin !== null) {
            return 'b2b';
        }

        return $bill->is_inter_state && (int) $bill->total_paise > self::B2CL_LIMIT_PAISE ? 'b2cl' : 'b2cs';
    }

    private function zero(): array
    {
        return array_fill_keys(self::TAX, 0);
    }

    /** Taxable value and tax per (non-zero) GST rate. */
    private function rates(Collection $items, int $sign): array
    {
        $by = [];
        foreach ($items as $item) {
            $rate = (int) $item->gst_rate_bp;
            if ($rate === 0) {
                continue;
            }
            $by[$rate] ??= ['gst_rate_bp' => $rate] + $this->zero();
            foreach (self::TAX as $k) {
                $by[$rate][$k] += $sign * (int) $item->{$k};
            }
        }
        ksort($by);

        return array_values($by);
    }

    private function add(array &$row, array $rates): void
    {
        foreach ($rates as $r) {
            foreach (self::TAX as $k) {
                $row[$k] += $r[$k];
            }
        }
    }

    private function invoiceRow(Bill $bill, array $rates): array
    {
        return [
            'invoice_no' => $bill->invoice_no,
            'invoice_date' => $bill->billDate(),
            'invoice_value_paise' => (int) $bill->total_paise,
            'place_of_supply' => $bill->place_of_supply,
            'reverse_charge' => 'N',
            'invoice_type' => 'Regular',
            'gstin' => $bill->customer_gstin,
            'name' => $bill->customer_name,
            'rates' => $rates,
        ];
    }

    private function addB2cs(array &$b2cs, Bill $bill, array $rates, int $sign): void
    {
        foreach ($rates as $r) {
            $key = sprintf('%s|%05d|%s', $bill->place_of_supply, $r['gst_rate_bp'], $bill->is_inter_state ? 'inter' : 'intra');
            $b2cs[$key] ??= ['place_of_supply' => $bill->place_of_supply, 'gst_rate_bp' => $r['gst_rate_bp'],
                'supply_type' => $bill->is_inter_state ? 'INTER' : 'INTRA', 'type' => 'OE'] + $this->zero();
            foreach (self::TAX as $k) {
                $b2cs[$key][$k] += $sign * $r[$k];
            }
        }
    }

    private function addNil(array &$nil, Bill $bill, object $item, int $sign): void
    {
        $key = ($bill->is_inter_state ? 'inter' : 'intra').'_'.($bill->customer_gstin ? 'registered' : 'unregistered');
        $nil[$key] ??= ['supply' => $key, 'nil_rated_paise' => 0];
        $nil[$key]['nil_rated_paise'] += $sign * (int) $item->taxable_paise;
    }

    private function addHsn(array &$hsn, string $section, object $item, int $qty, int $sign): void
    {
        $code = $item->hsn ?: '';
        $key = sprintf('%s|%s|%05d|%s', $section, $code, (int) $item->gst_rate_bp, $item->unit ?? '');
        $hsn[$key] ??= ['section' => $section, 'hsn' => $code ?: null, 'unit' => $item->unit, 'gst_rate_bp' => (int) $item->gst_rate_bp,
            'qty' => 0, 'total_value_paise' => 0] + $this->zero();
        $hsn[$key]['qty'] += $sign * $qty;
        $hsn[$key]['total_value_paise'] += $sign * (int) $item->total_paise;
        foreach (self::TAX as $k) {
            $hsn[$key][$k] += $sign * (int) $item->{$k};
        }
    }

    /** @param  Collection<int, array{0: string, 1: string, 2: int, 3: bool}>  $docs */
    private function documentRow(string $nature, Collection $docs): array
    {
        $sorted = $docs->sortBy(fn ($d) => sprintf('%s|%09d', $d[1], $d[2]))->values();

        return [
            'nature' => $nature,
            'from' => $sorted->first()[0] ?? null,
            'to' => $sorted->last()[0] ?? null,
            'total' => $sorted->count(),
            'cancelled' => $sorted->filter(fn ($d) => $d[3])->count(),
            'net_issued' => $sorted->reject(fn ($d) => $d[3])->count(),
        ];
    }

    private function sumDocs(Collection $docs): array
    {
        $out = ['count' => $docs->count(), 'total_paise' => 0] + $this->zero();
        foreach ($docs as $d) {
            $out['total_paise'] += (int) $d->total_paise;
            foreach (self::TAX as $k) {
                $out[$k] += (int) $d->{$k};
            }
        }

        return $out;
    }

    private function net(array $a, array $b): array
    {
        $out = [];
        foreach (['total_paise', ...self::TAX] as $k) {
            $out[$k] = $a[$k] - $b[$k];
        }

        return $out;
    }
}
