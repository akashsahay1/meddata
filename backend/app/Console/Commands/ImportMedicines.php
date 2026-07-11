<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class ImportMedicines extends Command
{
    protected $signature = 'medicines:import {path=/Users/akash/Desktop/meddata/assets/indian_medicine_data.csv}';

    protected $description = 'Stream the Indian medicine CSV into the medicines_master table (idempotent, chunked).';

    private const BATCH_SIZE = 1000;

    private const PROGRESS_EVERY = 20000;

    public function handle(): int
    {
        $path = $this->argument('path');

        if (! is_readable($path)) {
            $this->error("CSV not readable at: {$path}");

            return self::FAILURE;
        }

        $handle = fopen($path, 'rb');

        if ($handle === false) {
            $this->error("Could not open CSV at: {$path}");

            return self::FAILURE;
        }

        // Idempotent re-runs: start from a clean table each time.
        DB::table('medicines_master')->truncate();

        // Header row. Expected columns (order matters):
        // id,name,price(₹),Is_discontinued,manufacturer_name,type,pack_size_label,short_composition1,short_composition2
        $header = fgetcsv($handle, null, ',', '"', '');

        if ($header === false) {
            fclose($handle);
            $this->error('CSV appears to be empty.');

            return self::FAILURE;
        }

        $batch = [];
        $inserted = 0;
        $skipped = 0;

        while (($row = fgetcsv($handle, null, ',', '"', '')) !== false) {
            $mapped = $this->mapRow($row);

            if ($mapped === null) {
                $skipped++;

                continue;
            }

            $batch[] = $mapped;

            if (count($batch) >= self::BATCH_SIZE) {
                $inserted += $this->flush($batch, $skipped);
                $batch = [];

                if ($inserted % self::PROGRESS_EVERY < self::BATCH_SIZE) {
                    $this->info("Imported {$inserted} rows...");
                }
            }
        }

        // Final partial batch.
        if ($batch !== []) {
            $inserted += $this->flush($batch, $skipped);
        }

        fclose($handle);

        $this->info("Done. Inserted {$inserted} rows, skipped {$skipped} bad rows.");
        $this->info('Table count: '.DB::table('medicines_master')->count());

        return self::SUCCESS;
    }

    /**
     * Map one raw CSV row to a DB record, or null if it is unusable.
     *
     * @param  array<int, string|null>  $row
     * @return array<string, mixed>|null
     */
    private function mapRow(array $row): ?array
    {
        // Columns by position:
        // 0 id, 1 name, 2 price, 3 is_discontinued, 4 manufacturer,
        // 5 type, 6 pack_size, 7 short_composition1, 8 short_composition2
        $id = isset($row[0]) ? (int) trim((string) $row[0]) : 0;
        $name = isset($row[1]) ? trim((string) $row[1]) : '';

        if ($id <= 0 || $name === '') {
            return null;
        }

        $comp1 = isset($row[7]) ? trim((string) $row[7]) : '';
        $comp2 = isset($row[8]) ? trim((string) $row[8]) : '';
        $composition = $comp2 !== '' ? trim($comp1.', '.$comp2) : $comp1;
        $composition = trim($composition, " \t\n\r\0\x0B,");

        return [
            'id' => $id,
            'name' => $name,
            'name_norm' => mb_strtolower($name),
            'manufacturer' => $this->nullify($row[4] ?? null),
            'type' => $this->nullify($row[5] ?? null),
            'pack_size' => $this->nullify($row[6] ?? null),
            'composition' => $composition !== '' ? $composition : null,
            'price' => $this->parsePrice($row[2] ?? null),
            'is_discontinued' => strtoupper(trim((string) ($row[3] ?? ''))) === 'TRUE',
        ];
    }

    /**
     * Insert a batch, isolating failures so one bad batch is retried row by row
     * and only genuinely bad rows are dropped rather than killing the import.
     *
     * @param  array<int, array<string, mixed>>  $batch
     */
    private function flush(array $batch, int &$skipped): int
    {
        try {
            DB::table('medicines_master')->insert($batch);

            return count($batch);
        } catch (\Throwable $e) {
            // Fall back to per-row inserts so a single offender does not
            // discard the whole batch.
            $ok = 0;

            foreach ($batch as $record) {
                try {
                    DB::table('medicines_master')->insert($record);
                    $ok++;
                } catch (\Throwable $inner) {
                    $skipped++;
                }
            }

            return $ok;
        }
    }

    private function nullify(?string $value): ?string
    {
        $value = trim((string) $value);

        return $value === '' ? null : $value;
    }

    private function parsePrice(?string $value): ?float
    {
        $value = trim((string) $value);

        if ($value === '') {
            return null;
        }

        // Strip any currency symbol / commas, keep digits and decimal point.
        $clean = preg_replace('/[^0-9.]/', '', $value);

        return ($clean === '' || $clean === null) ? null : (float) $clean;
    }
}
