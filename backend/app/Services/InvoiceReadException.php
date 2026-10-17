<?php

namespace App\Services;

use RuntimeException;
use Throwable;

/**
 * Reading an invoice failed. The message is safe to show to the shop owner;
 * `errorCode` is machine-readable, `retryable` says whether trying again
 * later may help (service busy / unreachable), `slip` marks a reply the
 * model may well get right on a second read (no lines found, broken JSON),
 * and `raw` keeps the model's text when it was unusable.
 */
class InvoiceReadException extends RuntimeException
{
    public function __construct(
        public readonly string $errorCode,
        string $message,
        public readonly bool $retryable = false,
        public readonly ?string $raw = null,
        ?Throwable $previous = null,
        public readonly bool $slip = false,
    ) {
        parent::__construct($message, 0, $previous);
    }
}
