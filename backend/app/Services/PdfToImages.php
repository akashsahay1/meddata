<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Imagick;
use RuntimeException;
use Throwable;

/**
 * Turns a PDF invoice into one JPEG per page for the vision model, which
 * takes images only (at most MAX_PAGES per request).
 *
 * Needs php-imagick with Ghostscript, and an ImageMagick policy that allows
 * reading PDF. When the server can't (or the file is broken) the scan fails
 * with `pdf_unsupported` and the real reason goes to the log.
 */
class PdfToImages
{
    public const MAX_PAGES = 3;

    /** Enough for small print on an A4 bill, well under the image size limit. */
    private const DPI = 170;

    /**
     * @return list<string> JPEG bytes, one per page
     *
     * @throws InvoiceReadException
     */
    public function convert(string $pdf): array
    {
        try {
            $pages = $this->pageCount($pdf);
        } catch (Throwable $e) {
            throw $this->unsupported($e);
        }

        if ($pages > self::MAX_PAGES) {
            throw new InvoiceReadException('too_many_pages',
                "This PDF has {$pages} pages. Scan up to ".self::MAX_PAGES.' pages at a time.');
        }

        try {
            return $this->render($pdf);
        } catch (Throwable $e) {
            throw $this->unsupported($e);
        }
    }

    protected function pageCount(string $pdf): int
    {
        if (! extension_loaded('imagick')) {
            throw new RuntimeException('php-imagick is not installed');
        }
        $im = new Imagick;
        $im->pingImageBlob($pdf);

        return $im->getNumberImages();
    }

    /** @return list<string> */
    protected function render(string $pdf): array
    {
        $im = new Imagick;
        $im->setResolution(self::DPI, self::DPI);   // must come before reading
        $im->readImageBlob($pdf);

        $pages = [];
        for ($i = 0, $n = $im->getNumberImages(); $i < $n; $i++) {
            $im->setIteratorIndex($i);
            $page = $im->getImage();
            // Transparent areas would turn black in a JPEG.
            $page->setImageBackgroundColor('white');
            $flat = $page->mergeImageLayers(Imagick::LAYERMETHOD_FLATTEN);
            $flat->setImageFormat('jpeg');
            $flat->setImageCompressionQuality(85);
            $flat->stripImage();
            $pages[] = $flat->getImageBlob();
        }
        if ($pages === []) {
            throw new RuntimeException('no pages rendered');
        }

        return $pages;
    }

    private function unsupported(Throwable $e): InvoiceReadException
    {
        Log::warning('Invoice scan: PDF could not be converted to images: '.$e->getMessage());

        return new InvoiceReadException('pdf_unsupported',
            'Could not open this PDF on the server. Please send a photo of the invoice instead.', previous: $e);
    }
}
