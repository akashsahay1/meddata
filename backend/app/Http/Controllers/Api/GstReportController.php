<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\GstReportService;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * GSTR-1 / GSTR-3B style monthly summaries, for review by the shop's CA
 * (not a filing). Amounts in paise.
 */
class GstReportController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly GstReportService $reports,
    ) {}

    /** GET /gst/gstr1?month=Y-m */
    public function gstr1(Request $request): JsonResponse
    {
        $month = $request->validate(['month' => ['required', 'date_format:Y-m']])['month'];

        return response()->json($this->reports->gstr1($this->shops->forUser($request->user()), $month));
    }

    /** GET /gst/gstr3b?month=Y-m */
    public function gstr3b(Request $request): JsonResponse
    {
        $month = $request->validate(['month' => ['required', 'date_format:Y-m']])['month'];

        return response()->json($this->reports->gstr3b($this->shops->forUser($request->user()), $month));
    }
}
