<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\ProfitReportService;
use App\Services\ShopService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/** Reports computed from the shop's server data (bills). */
class ReportController extends Controller
{
    public function __construct(
        private readonly ShopService $shops,
        private readonly ProfitReportService $profit,
    ) {}

    /**
     * GET /reports/profit?from=Y-m-d&to=Y-m-d
     * Gross profit and margin by day, product and category, from the final
     * bills of the user's shop. See ProfitReportService for the basis.
     */
    public function profit(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => ['required', 'date_format:Y-m-d'],
            'to' => ['required', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
        $days = (int) Carbon::parse($data['from'])->diffInDays(Carbon::parse($data['to'])) + 1;
        if ($days > ProfitReportService::MAX_DAYS) {
            $message = 'Choose a range of at most '.ProfitReportService::MAX_DAYS.' days.';

            return response()->json(['message' => $message, 'errors' => ['to' => [$message]]], 422);
        }
        $shop = $this->shops->forUser($request->user());

        return response()->json($this->profit->build($shop, $data['from'], $data['to']));
    }
}
