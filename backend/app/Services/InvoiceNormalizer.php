<?php

namespace App\Services;

/**
 * Turns the invoice JSON the AI returned into predictable values: trimmed
 * strings (null when blank), dates as Y-m-d, money and percentages as
 * floats, quantities as ints. Lenient by design: a value it can't make sense
 * of becomes null for the user to fill in during review instead of failing
 * the whole scan. Lines without a product name are dropped.
 */
class InvoiceNormalizer
{
    private const MONTHS = [
        'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
        'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12,
    ];

    /** Placeholders that mean "not printed". */
    private const BLANKS = ['null', 'none', 'nil', 'n/a', 'na', '-', '--', '.'];

    public function normalize(array $raw): array
    {
        $items = [];
        foreach (is_array($raw['items'] ?? null) ? $raw['items'] : [] as $row) {
            if (! is_array($row) || ($name = $this->text($row['product_name'] ?? null)) === null) {
                continue;
            }
            $items[] = [
                'product_name' => $name,
                'manufacturer' => $this->text($row['manufacturer'] ?? null),
                'pack' => $this->text($row['pack'] ?? null, 32),
                'batch_no' => $this->text($row['batch_no'] ?? null, 64),
                // Expiry printed as month/year means "usable through that month".
                'expiry_date' => $this->date($row['expiry_date'] ?? null, endOfMonth: true),
                'mfg_date' => $this->date($row['mfg_date'] ?? null),
                'quantity' => $this->quantity($row['quantity'] ?? null),
                'free_quantity' => $this->quantity($row['free_quantity'] ?? null) ?? 0,
                'mrp' => $this->money($row['mrp'] ?? null),
                'purchase_rate' => $this->money($row['purchase_rate'] ?? null),
                'discount_percent' => $this->percent($row['discount_percent'] ?? null),
                'gst_percent' => $this->percent($row['gst_percent'] ?? null),
                'hsn' => $this->hsn($row['hsn'] ?? null),
                'barcode' => $this->barcode($row['barcode'] ?? null),
            ];
        }

        return [
            'supplier_name' => $this->text($raw['supplier_name'] ?? null),
            'supplier_gstin' => $this->gstin($raw['supplier_gstin'] ?? null),
            'invoice_no' => $this->text($raw['invoice_no'] ?? null, 64),
            'invoice_date' => $this->date($raw['invoice_date'] ?? null),
            'notes' => $this->text($raw['notes'] ?? null, 1000),
            'items' => $items,
        ];
    }

    /** Trimmed, single-spaced text; null when blank or a "n/a" placeholder. */
    public function text(mixed $value, int $max = 255): ?string
    {
        if (! is_string($value) && ! is_int($value) && ! is_float($value)) {
            return null;
        }
        $s = trim((string) preg_replace('/\s+/u', ' ', (string) $value));
        if ($s === '' || in_array(mb_strtolower($s), self::BLANKS, true)) {
            return null;
        }

        return mb_substr($s, 0, $max);
    }

    /**
     * A date as Y-m-d, or null. Day-first like Indian invoices (05/06/27 is
     * 5 June 2027); two-digit years are 20xx. A month-only date ("06/27",
     * "Jun-2027", "2027-06") becomes the last day of that month when
     * $endOfMonth (expiry), else the first (manufacture).
     */
    public function date(mixed $value, bool $endOfMonth = false): ?string
    {
        $s = $this->text($value, 40);
        if ($s === null) {
            return null;
        }
        $s = mb_strtolower($s);
        $s = (string) preg_replace('/^(exp(iry)?|mfg|mfd|date)\b[\s.:]*/', '', $s);
        $s = (string) preg_replace('/^(\d{4}-\d{2}-\d{2})[t\s].*$/', '$1', $s); // drop a time part
        $sep = '[-\/.\s]+';

        return match (true) {
            (bool) preg_match("/^(\d{4}){$sep}(\d{1,2}){$sep}(\d{1,2})$/", $s, $m) => $this->ymd((int) $m[1], (int) $m[2], (int) $m[3]),
            (bool) preg_match("/^(\d{4}){$sep}(\d{1,2})$/", $s, $m) => $this->ym((int) $m[1], (int) $m[2], $endOfMonth),
            (bool) preg_match("/^(\d{1,2}){$sep}(\d{1,2}){$sep}(\d{4}|\d{2})$/", $s, $m) => $this->ymd($this->year($m[3]), (int) $m[2], (int) $m[1]),
            (bool) preg_match("/^(\d{1,2}){$sep}(\d{4}|\d{2})$/", $s, $m) => $this->ym($this->year($m[2]), (int) $m[1], $endOfMonth),
            (bool) preg_match("/^(\d{1,2})[-\/.\s]*([a-z]{3,9})[-\/.,'\s]*(\d{4}|\d{2})$/", $s, $m) => $this->ymd($this->year($m[3]), $this->month($m[2]), (int) $m[1]),
            (bool) preg_match("/^([a-z]{3,9})[-\/.,'\s]*(\d{4}|\d{2})$/", $s, $m) => $this->ym($this->year($m[2]), $this->month($m[1]), $endOfMonth),
            (bool) preg_match("/^([a-z]{3,9})\s+(\d{1,2}),?\s+(\d{4})$/", $s, $m) => $this->ymd((int) $m[3], $this->month($m[1]), (int) $m[2]),
            default => null,
        };
    }

    /** A plain number from a number or a printed amount ("₹1,234.50", "12%"). */
    public function number(mixed $value): ?float
    {
        if (is_int($value) || is_float($value)) {
            return is_finite((float) $value) ? (float) $value : null;
        }
        if (! is_string($value)) {
            return null;
        }
        $s = str_replace([',', '₹', ' '], '', mb_strtolower(trim($value)));
        $s = rtrim((string) preg_replace('/^(rs\.?|inr)/', '', $s), '%');

        return preg_match('/^-?\d+(\.\d+)?$/', $s) ? (float) $s : null;
    }

    public function money(mixed $value): ?float
    {
        $n = $this->number($value);

        return $n === null || $n < 0 ? null : round($n, 2);
    }

    public function percent(mixed $value): ?float
    {
        $n = $this->number($value);

        return $n === null || $n < 0 || $n > 100 ? null : round($n, 2);
    }

    public function quantity(mixed $value): ?int
    {
        $n = $this->number($value);

        return $n === null || $n < 0 ? null : (int) round($n);
    }

    private function gstin(mixed $value): ?string
    {
        $s = strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', (string) $this->text($value)));

        return $s === '' ? null : substr($s, 0, 20);
    }

    /** HSN/SAC codes are 2-8 digits. */
    private function hsn(mixed $value): ?string
    {
        $s = (string) preg_replace('/\D/', '', (string) $this->text($value));

        return strlen($s) >= 2 && strlen($s) <= 8 ? $s : null;
    }

    /** EAN-8 .. GTIN-14 style codes; anything else is not a barcode. */
    private function barcode(mixed $value): ?string
    {
        $s = (string) preg_replace('/[^A-Za-z0-9]/', '', (string) $this->text($value));

        return strlen($s) >= 6 && strlen($s) <= 20 ? $s : null;
    }

    private function year(string $y): int
    {
        return strlen($y) === 2 ? 2000 + (int) $y : (int) $y;
    }

    private function month(string $name): int
    {
        return self::MONTHS[substr($name, 0, 3)] ?? 0;
    }

    private function ymd(int $y, int $m, int $d): ?string
    {
        if ($y < 2000 || $y > 2100 || ! checkdate($m, $d, $y)) {
            return null;
        }

        return sprintf('%04d-%02d-%02d', $y, $m, $d);
    }

    private function ym(int $y, int $m, bool $endOfMonth): ?string
    {
        if ($y < 2000 || $y > 2100 || $m < 1 || $m > 12) {
            return null;
        }
        $day = $endOfMonth ? (int) date('t', (int) mktime(0, 0, 0, $m, 1, $y)) : 1;

        return sprintf('%04d-%02d-%02d', $y, $m, $day);
    }
}
