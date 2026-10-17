<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Process;

/**
 * The text layer of a PDF made by billing software (Marg, Busy, Tally, ...),
 * with the column layout kept. Reading that text is exact and far cheaper
 * than reading page images, so GroqInvoiceReader prefers it.
 *
 * Needs `pdftotext` (poppler-utils). Returns null for a scanned PDF (no
 * text inside), a broken file, or when the tool is missing; the reader then
 * falls back to page images.
 */
class PdfText
{
    /** Fewer letters and digits than this is a scan with a stray stamp or page number, not a bill. */
    private const MIN_CHARS = 200;

    public function extract(string $pdf): ?string
    {
        $result = Process::input($pdf)->timeout(30)->run(['pdftotext', '-layout', '-enc', 'UTF-8', '-', '-']);
        if ($result->failed()) {
            Log::warning('Invoice scan: pdftotext failed, reading page images instead: '
                .trim($result->errorOutput() ?: 'exit '.$result->exitCode()));

            return null;
        }

        $text = $result->output();

        return preg_match_all('/[\p{L}\p{N}]/u', $text) >= self::MIN_CHARS ? $text : null;
    }
}
