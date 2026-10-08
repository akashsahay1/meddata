<?php

namespace App\Support;

/**
 * Pieces per pack of a product (tablets per strip, ml per bottle). Stock
 * is always in pieces; a batch's MRP and purchase rate are per pricePack()
 * pieces: the strip when the pack size applies, else one unit. Mirrors
 * app/lib/domain/pack_size.dart.
 */
final class PackSize
{
    /** Units counted per piece of a pack; every other unit counts whole packs. */
    public const PIECE_UNITS = ['Tablets', 'Capsules', 'ML'];

    public static function applies(?string $unit, int $packSize): bool
    {
        return $packSize > 1 && in_array($unit, self::PIECE_UNITS, true);
    }

    /** Pieces one price covers. */
    public static function pricePack(?string $unit, ?int $packSize): int
    {
        $packSize = max(1, (int) $packSize);

        return self::applies($unit, $packSize) ? $packSize : 1;
    }
}
