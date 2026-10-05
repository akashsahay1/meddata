<?php

namespace App\Support;

/**
 * Loose comparison of a medicine name as printed on a supplier invoice with
 * the name a shop typed ("DOLO-650 TAB 15'S" vs "Dolo 650"). Case, word
 * order, punctuation, "mg", strip counts ("15's", "1x10") and dosage-form
 * spellings (tab/tablet, syp/syrup, ...) don't matter. A dosage form is only
 * ignored when one of the two names has none, so "Crocin Syrup" never
 * matches "Crocin Tab". The app applies the same rules
 * (app/lib/domain/medicine_name_key.dart).
 */
final class MedicineNameKey
{
    /** Spellings of dosage forms => canonical form token. */
    private const FORMS = [
        'tab' => 'tab', 'tabs' => 'tab', 'tablet' => 'tab', 'tablets' => 'tab',
        'cap' => 'cap', 'caps' => 'cap', 'capsule' => 'cap', 'capsules' => 'cap',
        'syp' => 'syp', 'syr' => 'syp', 'syrup' => 'syp',
        'susp' => 'susp', 'suspension' => 'susp',
        'inj' => 'inj', 'injection' => 'inj', 'vial' => 'inj', 'amp' => 'inj', 'ampoule' => 'inj',
        'oint' => 'oint', 'ointment' => 'oint',
        'cream' => 'cream', 'crm' => 'cream',
        'gel' => 'gel',
        'drop' => 'drops', 'drops' => 'drops',
        'lotion' => 'lotion',
        'sachet' => 'sachet', 'sachets' => 'sachet',
        'powder' => 'powder', 'pdr' => 'powder',
        'sol' => 'sol', 'solution' => 'sol',
    ];

    /**
     * Canonical tokens in printed order: letters and numbers split apart,
     * "mg" and pack counts dropped, dosage forms canonicalised.
     *
     * @return list<string>
     */
    public static function tokens(?string $name): array
    {
        preg_match_all('/[a-z]+|\d+(?:\.\d+)?/u', mb_strtolower((string) $name), $m);
        $raw = $m[0];
        $out = [];
        $n = count($raw);
        for ($i = 0; $i < $n; $i++) {
            $t = $raw[$i];
            $next = $raw[$i + 1] ?? null;
            $isNumber = ctype_digit(str_replace('.', '', $t));
            if ($isNumber && $next === 's') {           // 15's, 10s
                $i++;

                continue;
            }
            if ($isNumber && $next === 'x' && isset($raw[$i + 2]) && ctype_digit($raw[$i + 2])) {
                $i += 2;                                // 1x10, 10 x 10

                continue;
            }
            if ($t === 'mg') {
                continue;
            }
            $out[] = self::FORMS[$t] ?? $t;
        }

        return $out;
    }

    /**
     * What two names are compared on: the sorted canonical tokens ("650
     * dolo tab"), the same without dosage forms ("650 dolo"), and whether
     * the name has a form at all.
     *
     * @return array{key: string, base: string, form: bool}
     */
    public static function signature(?string $name): array
    {
        $tokens = self::tokens($name);
        $base = array_values(array_diff($tokens, self::FORMS));
        sort($tokens);
        sort($base);

        return [
            'key' => implode(' ', $tokens),
            'base' => implode(' ', $base),
            'form' => count($base) !== count($tokens),
        ];
    }

    /** Whether two signatures most likely mean the same medicine. */
    public static function matches(array $a, array $b): bool
    {
        if ($a['key'] === '') {
            return false;
        }
        if ($a['key'] === $b['key']) {
            return true;
        }

        return $a['base'] !== '' && $a['base'] === $b['base'] && (! $a['form'] || ! $b['form']);
    }

    public static function same(?string $a, ?string $b): bool
    {
        return self::matches(self::signature($a), self::signature($b));
    }
}
