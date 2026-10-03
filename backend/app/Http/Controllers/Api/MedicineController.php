<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MedicineMaster;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MedicineController extends Controller
{
    /**
     * Search the shared medicine catalog (CSV seed + medicines added by shops).
     *
     * GET /api/v1/medicines/search?q=<name prefix>
     * GET /api/v1/medicines/search?barcode=<code>
     */
    public function search(Request $request): JsonResponse
    {
        $barcode = trim((string) $request->query('barcode', ''));
        $q = trim((string) $request->query('q', ''));

        if ($barcode !== '') {
            $query = MedicineMaster::query()->where('barcode', $barcode);
        } elseif (mb_strlen($q) >= 2) {
            $query = MedicineMaster::query()
                ->where('name_norm', 'like', $this->escapeLike(MedicineMaster::norm($q)).'%');
        } else {
            return response()->json(['results' => []]);
        }

        $rows = $query->orderBy('is_discontinued')
            ->orderBy('name')
            ->limit(15)
            ->get();

        $results = $rows->map(fn (MedicineMaster $m): array => [
            'id' => (int) $m->id,
            'name' => $m->name,
            'manufacturer' => $m->manufacturer,
            'type' => $m->type,
            'pack_size' => $m->pack_size,
            'composition' => $m->composition,
            'price' => $m->price !== null ? (float) $m->price : null,
            'unit' => $this->deriveUnit($m->pack_size),
            'barcode' => $m->barcode,
            'hsn' => $m->hsn,
            'gst_rate_bp' => $m->gst_rate_bp,
            'source' => $m->source,
        ])->all();

        return response()->json(['results' => $results]);
    }

    /**
     * Derive an app-facing unit (one of AppConstants.units) from the free-text
     * pack_size label. Defaults to Tablets when nothing matches.
     */
    private function deriveUnit(?string $packSize): string
    {
        $label = mb_strtolower((string) $packSize);

        // Order matters: check the more specific / higher-signal tokens first.
        $map = [
            'capsule' => 'Capsules',
            'tablet' => 'Tablets',
            'vial' => 'Injections',
            'injection' => 'Injections',
            'syrup' => 'Bottles',
            'bottle' => 'Bottles',
            'ml' => 'ML',
            'sachet' => 'Sachets',
            'strip' => 'Strips',
            'cream' => 'Tubes',
            'ointment' => 'Tubes',
            'gel' => 'Tubes',
            'tube' => 'Tubes',
        ];

        foreach ($map as $needle => $unit) {
            if (str_contains($label, $needle)) {
                return $unit;
            }
        }

        return 'Tablets';
    }

    /** Escape LIKE wildcards in user input so they are matched literally. */
    private function escapeLike(string $value): string
    {
        return str_replace(['\\', '%', '_'], ['\\\\', '\\%', '\\_'], $value);
    }
}
