<?php

namespace App\Services;

use RuntimeException;
use Throwable;

/**
 * Reading an invoice failed. The message is safe to show to the shop owner;
 * `errorCode` is machine-readable, `retryable` says whether trying again
 * later may help (service busy / unreachable), and `raw` keeps the model's
 * text when it was unusable.
 */
class InvoiceReadException extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly bool $retryable = false,
        public readonly ?string $raw = null,
        ?Throwable $previous = null,
    ) {
        parent::__construct($message, 0, $previous);
    }
}
