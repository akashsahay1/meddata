<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MedicineMaster;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MedicineController extends Controller
{
    /**
     * Prefix search over the medicines master list.
     *
     * GET /api/v1/medicines/search?q=<string>
     */
    public function search(Request $request): JsonResponse
    {
        $q = trim((string) $request->query('q', ''));

        if (mb_strlen($q) < 2) {
            return response()->json(['results' => []]);
        }

        $prefix = mb_strtolower($q);

        $rows = MedicineMaster::query()
            ->where('name_norm', 'like', $this->escapeLike($prefix).'%')
            ->orderBy('name')
            ->limit(15)
            ->get(['id', 'name', 'manufacturer', 'type', 'pack_size', 'composition', 'price']);

        $results = $rows->map(fn (MedicineMaster $m): array => [
            'id' => (int) $m->id,
            'name' => $m->name,
            'manufacturer' => $m->manufacturer,
            'type' => $m->type,
            'pack_size' => $m->pack_size,
            'composition' => $m->composition,
            'price' => $m->price !== null ? (float) $m->price : null,
            'unit' => $this->deriveUnit($m->pack_size),
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
            'ml' => 'ml',
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
