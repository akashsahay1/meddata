<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ShopController extends Controller
{
    public function __construct(private readonly ShopService $shops) {}

    /** GET /shops/current — the user's shop (created on first use). */
    public function current(Request $request): JsonResponse
    {
        $shop = $this->shops->forUser($request->user());

        return response()->json([
            'shop' => $shop->toArray(),
            // Lets a newly logged-in device decide between "upload my local
            // data" (empty shop) and "merge or discard" (shop already has data).
            'has_data' => Product::withTrashed()->where('shop_id', $shop->id)->exists(),
        ]);
    }

    /** PATCH /shops/current */
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'gstin' => ['sometimes', 'nullable', 'string', 'size:15'],
            'state_code' => ['sometimes', 'nullable', 'string', 'size:2'],
            'drug_license_no' => ['sometimes', 'nullable', 'string', 'max:255'],
            'address' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:32'],
            'invoice_prefix' => ['sometimes', 'nullable', 'string', 'max:12'],
        ]);
        $shop = $this->shops->forUser($request->user());
        $shop->fill($data)->save();

        return response()->json(['shop' => $shop->toArray()]);
    }
}
