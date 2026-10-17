<?php

namespace Tests\Feature;

use App\Services\PdfText;
use Imagick;
use ImagickPixel;
use Tests\TestCase;

/** Real extraction: needs pdftotext (poppler-utils), so it is skipped without it. */
class PdfTextTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        if (trim((string) shell_exec('command -v pdftotext')) === '') {
            $this->markTestSkipped('Needs pdftotext (poppler-utils).');
        }
    }

    /** A one-page PDF with real text, as billing software makes them. */
    private function textPdf(array $lines): string
    {
        $stream = "BT /F1 9 Tf 40 800 Td 12 TL\n";
        foreach ($lines as $line) {
            $stream .= '('.addcslashes($line, '()\\').") Tj T*\n";
        }
        $stream .= 'ET';
        $objects = [
            '<< /Type /Catalog /Pages 2 0 R >>',
            '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
            '<< /Length '.strlen($stream)." >>\nstream\n{$stream}\nendstream",
            '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
        ];
        $pdf = "%PDF-1.4\n";
        $offsets = [];
        foreach ($objects as $i => $body) {
            $offsets[] = strlen($pdf);
            $pdf .= ($i + 1)." 0 obj\n{$body}\nendobj\n";
        }
        $xref = strlen($pdf);
        $pdf .= "xref\n0 ".(count($objects) + 1)."\n0000000000 65535 f \n";
        foreach ($offsets as $o) {
            $pdf .= sprintf("%010d 00000 n \n", $o);
        }

        return $pdf.'trailer << /Size '.(count($objects) + 1)." /Root 1 0 R >>\nstartxref\n{$xref}\n%%EOF";
    }

    public function test_the_text_of_a_billing_software_pdf_is_read_exactly(): void
    {
        $lines = ['SHREE BALAJI PHARMA DISTRIBUTORS        TAX INVOICE  SBP/2627/04518'];
        foreach (['Dolo 650 Tab    B21265  07/28', 'Montair LC Tab  B84115  02/27', 'Atorva 10 Tab   T71027  10/28'] as $i => $item) {
            $lines[] = ($i + 1)."  {$item}  3004  10  135.00  93.35  12  1,867.00";
        }
        $lines[] = 'Total Taxable 18,602.58   CGST 1,116.15   SGST 1,116.15   GRAND TOTAL 20,835.00';

        $text = app(PdfText::class)->extract($this->textPdf($lines));

        $this->assertNotNull($text);
        $this->assertStringContainsString('T71027', $text);
        $this->assertMatchesRegularExpression('/Atorva 10 Tab\s+T71027\s+10\/28/', $text, 'columns stay on one line');
    }

    public function test_a_scanned_pdf_or_a_broken_file_has_no_text(): void
    {
        $scan = new Imagick;   // a page that is only a picture
        $scan->newImage(595, 842, new ImagickPixel('white'));
        $scan->setImageFormat('pdf');

        $this->assertNull(app(PdfText::class)->extract($scan->getImagesBlob()));
        $this->assertNull(app(PdfText::class)->extract('%PDF-1.4 not really a pdf'));
        $this->assertNull(app(PdfText::class)->extract($this->textPdf(['Page 1'])), 'a stray page number is not a bill');
    }
}
