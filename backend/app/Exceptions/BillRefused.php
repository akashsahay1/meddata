<?php

namespace App\Exceptions;

use Illuminate\Http\JsonResponse;
use RuntimeException;

/**
 * A bill the server would not create: a price changed since the device
 * loaded it (409), not enough stock, or a batch that can't be sold (422).
 * Thrown inside the bill transaction, so nothing is written - not even an
 * invoice number. The payload tells the device which lines to fix.
 */
class BillRefused extends RuntimeException
{
    public function __construct(
        public readonly int $status,
        public readonly array $payload,
    ) {
        parent::__construct($payload['message'] ?? 'Bill refused');
    }

    public function render(): JsonResponse
    {
        return response()->json($this->payload, $this->status);
    }
}
