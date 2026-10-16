"""Turns `flutter test --reporter json` output into GitHub annotations.

Usage: python3 annotate_tests.py results.json
Prints a readable summary for the log, one annotation per failed test (with
the error and the start of its stack trace) and a notice with the totals.
A test file that doesn't compile shows up as its failed "loading" test.
"""
import json
import sys


def esc(text):
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def esc_prop(text):
    return esc(text).replace(':', '%3A').replace(',', '%2C')


def main(path):
    tests, errors, done = {}, {}, {}
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line.startswith('{'):
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            kind = event.get('type')
            if kind == 'testStart':
                tests[event['test']['id']] = event['test']
            elif kind == 'error':
                text = event.get('error', '') + '\n' + '\n'.join(event.get('stackTrace', '').splitlines()[:12])
                errors.setdefault(event['testID'], []).append(text)
            elif kind == 'testDone':
                done[event['testID']] = event

    passed = sum(1 for d in done.values() if d.get('result') == 'success' and not d.get('skipped') and not d.get('hidden'))
    skipped = sum(1 for d in done.values() if d.get('skipped'))
    failed = [i for i, d in done.items() if d.get('result') in ('failure', 'error')]

    for test_id in failed:
        test = tests.get(test_id, {})
        name = test.get('name', '?')
        where = (test.get('root_url') or test.get('url') or '').split('/test/', 1)[-1]
        detail = '\n\n'.join(errors.get(test_id, []))[:6000]
        print(f'FAILED: {name} ({where})\n{detail}\n')
        print(f'::error title={esc_prop(name[:180])}::{esc(where + chr(10) + detail)}')
    summary = f'{passed} passed, {skipped} skipped, {len(failed)} failed'
    print(summary)
    print(f'::notice title=flutter test::{summary}')


if __name__ == '__main__':
    main(sys.argv[1])
