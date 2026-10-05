<?php

namespace App\Exceptions;

use Illuminate\Http\JsonResponse;
use RuntimeException;

/**
 * An accounting request the server would not carry out (e.g. returning more
 * than was sold, cancelling a bill that has a credit note). Thrown inside
 * the document's transaction, so nothing is written and no number is used.
 * Renders as {message, error, ...details} with the given status.
 */
class ApiRefused extends RuntimeException
{
    public function __construct(
        public readonly int $status,
        public readonly string $error,
        string $message,
        public readonly array $details = [],
    ) {
        parent::__construct($message);
    }

    public function render(): JsonResponse
    {
        return response()->json(['message' => $this->getMessage(), 'error' => $this->error] + $this->details, $this->status);
    }
}
