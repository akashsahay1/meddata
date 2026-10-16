"""Turns `flutter analyze --format=machine` output into GitHub annotations.

Usage: python3 annotate_analyze.py analyze.txt
Prints one annotation per issue (GitHub shows the first ten per step) and a
notice with the count, so the issues can be read without opening the log.
"""
import os
import sys


def esc(text):
    return text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def esc_prop(text):
    return esc(text).replace(':', '%3A').replace(',', '%2C')


def main(path):
    workspace = os.environ.get('GITHUB_WORKSPACE', '').rstrip('/') + '/'
    issues = []
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.rstrip('\n').split('|')
            if len(parts) < 8 or parts[0] not in ('ERROR', 'WARNING', 'INFO'):
                continue
            severity, _kind, code, file, row, col = parts[:6]
            message = '|'.join(parts[7:])
            issues.append((severity, code, file.replace(workspace, ''), row, col, message))
    for severity, code, file, row, col, message in issues:
        level = 'error' if severity == 'ERROR' else 'warning'
        print(f'::{level} file={esc_prop(file)},line={row},col={col},title={esc_prop(code)}::{esc(message)}')
    if issues:
        listing = '\n'.join(f'{f}:{r}:{c} {s} {code}: {m}' for s, code, f, r, c, m in issues)
        print(f'::error title=flutter analyze: {len(issues)} issue(s)::{esc(listing)}')
    print(f'::notice title=flutter analyze::{len(issues)} issue(s)')


if __name__ == '__main__':
    main(sys.argv[1])
