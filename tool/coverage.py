#!/usr/bin/env python3
"""Run package tests and merge LCOV by repository-relative source and line."""
import argparse
import os
from pathlib import Path
import subprocess
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = {
    'packages/mm_core': 'dart',
    'packages/mm_layout': 'dart',
    'packages/mm_data': 'dart',
    'packages/mm_design': 'flutter',
    'packages/mm_platform': 'flutter',
    'packages/mm_pdf': 'flutter',
    'apps/marginmind': 'flutter',
}


def merge(reports, root):
    lines = {}
    for package, report in reports:
        source = None
        count = 0
        for line in report.read_text().splitlines():
            if line.startswith('SF:'):
                path = Path(line[3:])
                if not path.is_absolute():
                    path = root / package / path
                try:
                    source = path.resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    source = None  # SDK / pub cache dependencies
                if source and (not source.startswith(('packages/', 'apps/')) or '/lib/' not in source):
                    source = None
            elif source and line.startswith('DA:'):
                number, hits, *_ = line[3:].split(',')
                key = (source, int(number))
                lines[key] = lines.get(key, 0) + int(hits)
                count += 1
        if count == 0:
            raise ValueError(f'No project coverage in {report}')
    if not lines:
        raise ValueError('No coverage records')
    return lines


def write_lcov(lines, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for source in sorted({s for s, _ in lines}):
            records = sorted((n, hits) for (s, n), hits in lines.items() if s == source)
            stream.write(f'SF:{source}\n')
            for number, hits in records:
                stream.write(f'DA:{number},{hits}\n')
            stream.write(f'LF:{len(records)}\nLH:{sum(h > 0 for _, h in records)}\nend_of_record\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report-only', action='store_true', help='Merge existing package reports without running tests')
    parser.add_argument('--minimum', type=float, default=80)
    args = parser.parse_args()
    if not 0 <= args.minimum <= 100:
        parser.error('--minimum must be between 0 and 100')
    reports = []
    for package, runner in PACKAGES.items():
        cwd = ROOT / package
        report = cwd / 'coverage/lcov.info'
        if not args.report_only:
            # Never accept a stale report after a failed or empty test run.
            shutil.rmtree(cwd / 'coverage', ignore_errors=True)
            if runner == 'dart':
                subprocess.run(['dart', 'test', '--coverage=coverage'], cwd=cwd, check=True)
                subprocess.run(['dart', 'run', 'coverage:format_coverage', '--lcov', '--in=coverage',
                                '--out=coverage/lcov.info', '--report-on=lib'], cwd=cwd, check=True)
            else:
                subprocess.run(['flutter', 'test', '--coverage'], cwd=cwd, check=True)
        reports.append((package, report))
    lines = merge(reports, ROOT)
    write_lcov(lines, ROOT / 'coverage/lcov.info')
    rows = ['| Package | Covered / lines | Coverage |', '| --- | ---: | ---: |']
    # Include libraries exercised through another package (e.g. mm_pdf).
    packages = sorted({'/'.join(source.split('/')[:2]) for source, _ in lines})
    for package in packages:
        hits = [h for (s, _), h in lines.items() if s.startswith(package + '/')]
        covered = sum(h > 0 for h in hits)
        rows.append(f'| {package} | {covered} / {len(hits)} | {100 * covered / len(hits):.2f}% |')
    covered = sum(h > 0 for h in lines.values())
    percent = 100 * covered / len(lines)
    rows.append(f'| **Total** | **{covered} / {len(lines)}** | **{percent:.2f}%** |')
    summary = '\n'.join(rows) + f'\n\nRequired: {args.minimum:g}%.\n'
    print(summary)
    (ROOT / 'coverage/summary.md').write_text(summary)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(summary)
    return 0 if percent >= args.minimum else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Coverage failed: {error}', file=sys.stderr)
        sys.exit(1)
