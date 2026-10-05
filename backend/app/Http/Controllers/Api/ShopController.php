<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Services\ShopService;
use App\Support\ShopDetails;
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

    /**
     * PATCH /shops/current — the details printed on invoices (legal name,
     * GSTIN, state, address, phone, drug licence no., invoice prefix) and
     * the GST rate for products that have none.
     */
    public function update(Request $request): JsonResponse
    {
        $request->replace(ShopDetails::prepare($request->all()));
        $data = $request->validate(ShopDetails::rules());
        $shop = $this->shops->forUser($request->user());
        $shop->fill(ShopDetails::merge($shop->only(array_keys(ShopDetails::rules())), $data))->save();

        return response()->json(['shop' => $shop->toArray()]);
    }
}
