<?php

namespace Tests\Feature;

use App\Services\GroqInvoiceReader;
use App\Services\InvoiceReadException;
use App\Services\PdfToImages;
use Imagick;
use ImagickDraw;
use ImagickPixel;
use Tests\TestCase;

/** Real conversion: needs php-imagick and Ghostscript, so it is skipped without them. */
class PdfToImagesTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        if (! extension_loaded('imagick') || trim((string) shell_exec('command -v gs')) === '') {
            $this->markTestSkipped('Needs php-imagick and Ghostscript (gs).');
        }
    }

    /** A4 pages; with $text, a printed line at the top and a footer at the very bottom. */
    private function pdf(int $pages, bool $text = false): string
    {
        $doc = new Imagick;
        for ($i = 0; $i < $pages; $i++) {
            $doc->newImage(595, 842, new ImagickPixel('white'));   // A4 at 72 dpi
            if ($text) {
                $draw = new ImagickDraw;   // dark bars stand in for printed lines
                $draw->rectangle(40, 50, 555, 62);
                $draw->rectangle(480, 822, 555, 832);
                $doc->drawImage($draw);
            }
            $doc->setImageFormat('pdf');
        }

        return $doc->getImagesBlob();
    }

    // The model sees each image at a fixed pixel budget; an A4 page that is
    // mostly blank (here: a header and a footer) wasted it on white space.
    public function test_blank_space_is_squeezed_out_but_the_print_keeps_its_resolution(): void
    {
        [$jpeg] = app(PdfToImages::class)->convert($this->pdf(1, text: true));

        [$w, $h] = getimagesizefromstring($jpeg);
        $this->assertLessThan(300, $h, 'the gap between header and footer is gone');
        $this->assertGreaterThan(1000, $w, 'the text is still rendered at ~170 dpi');
    }

    public function test_each_page_becomes_a_jpeg_within_the_size_limit(): void
    {
        $pages = app(PdfToImages::class)->convert($this->pdf(2));

        $this->assertCount(2, $pages);
        foreach ($pages as $jpeg) {
            $info = getimagesizefromstring($jpeg);
            $this->assertSame('image/jpeg', $info['mime']);
            $this->assertGreaterThan(1000, $info[1]);   // read at ~170 dpi, not 72
            $this->assertLessThanOrEqual(GroqInvoiceReader::MAX_IMAGE_BYTES, strlen($jpeg));
        }
    }

    public function test_a_pdf_over_three_pages_is_refused(): void
    {
        try {
            app(PdfToImages::class)->convert($this->pdf(4));
            $this->fail('Expected too_many_pages');
        } catch (InvoiceReadException $e) {
            $this->assertSame('too_many_pages', $e->errorCode);
            $this->assertSame('This PDF has 4 pages. Scan up to 3 pages at a time.', $e->getMessage());
        }
    }

    public function test_a_broken_pdf_fails_as_unsupported(): void
    {
        $this->expectExceptionObject(new InvoiceReadException('pdf_unsupported',
            'Could not open this PDF on the server. Please send a photo of the invoice instead.'));

        app(PdfToImages::class)->convert('%PDF-1.4 not really a pdf');
    }
}
