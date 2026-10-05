<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Gap-free numbers for credit notes (CN) and debit notes (DN): one counter
 * per shop, kind and financial year, bumped inside the document's
 * transaction while the caller holds the shop row lock. A refused document
 * rolls back and uses no number.
 */
final class DocumentSeries
{
    public const CREDIT_NOTE = 'CN';

    public const DEBIT_NOTE = 'DN';

    public static function next(int $shopId, string $kind, string $fy): int
    {
        $row = DB::table('document_series')
            ->where('shop_id', $shopId)
            ->where('kind', $kind)
            ->where('fy', $fy)
            ->lockForUpdate()
            ->first();
        $seq = ($row ? (int) $row->last_seq : 0) + 1;

        if ($row) {
            DB::table('document_series')->where('id', $row->id)
                ->update(['last_seq' => $seq, 'updated_at' => now()]);
        } else {
            DB::table('document_series')->insert([
                'shop_id' => $shopId,
                'kind' => $kind,
                'fy' => $fy,
                'last_seq' => $seq,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return $seq;
    }

    /** "CN/26-27/000001" (14 characters; GST allows 16). */
    public static function format(string $kind, string $fy, int $seq): string
    {
        return sprintf('%s/%s/%06d', $kind, $fy, $seq);
    }
}
