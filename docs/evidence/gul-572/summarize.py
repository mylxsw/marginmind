"""Summarize every measured chapter/parameter group, including slow ones."""
from collections import Counter, defaultdict
import csv
import gzip
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
rows = [json.loads(s) for s in gzip.open(HERE / 'linux.jsonl.gz', 'rt')]
assert rows[-1]['kind'] == 'done', 'Incomplete run'
environment = next(r for r in rows if r['kind'] == 'environment')
assert environment['release'] and environment['repeats'] == 30


def p95(values):
    return sorted(values)[math.ceil(len(values) * .95) - 1]


def stats(values):
    return {'count': len(values), 'p50_ms': sorted(values)[len(values) // 2] / 1000,
            'p95_ms': p95(values) / 1000, 'max_ms': max(values) / 1000}


groups = defaultdict(list)
for row in rows:
    if row['kind'] == 'layout':
        groups[(row['book'], row['chapter'], row['width'], row['font'])].append(row)
with (HERE / 'chapters.csv').open('w') as file:
    writer = csv.writer(file, lineterminator='\n')
    writer.writerow(['book', 'chapter', 'width', 'font', 'utf16', 'blocks', 'images', 'tables',
                     'samples', 'p50_ms', 'p95_ms', 'max_ms', 'work_p95_ms', 'wait_p95_ms', 'max_batch_ms'])
    for key, group in sorted(groups.items()):
        assert len(group) == 30
        timing = stats([r['us'] for r in group])
        writer.writerow([*key, *[group[0][k] for k in ['utf16', 'blocks', 'images', 'tables']],
                         len(group), timing['p50_ms'], timing['p95_ms'], timing['max_ms'],
                         p95([r['work_us'] for r in group]) / 1000,
                         p95([max(0, r['us'] - r['work_us']) for r in group]) / 1000,
                         max(r['max_batch_us'] for r in group) / 1000])
summary = {'host': rows[0], 'environment': environment, 'events': dict(Counter(r['kind'] for r in rows)),
           'books': {}, 'stress': {}, 'frames': {}, 'memory': [r for r in rows if r['kind'] == 'memory'],
           'image_failures': [r for r in rows if r['kind'] in ('missing_image', 'unsupported_image')],
           'anchor_failures': sum(not r['anchor_ok'] for r in rows if r['kind'] == 'layout')}
memory_samples = [r['pss_kib'] for r in rows if r['kind'] in ('memory_poll', 'memory')]
summary['sampled_peak_pss_kib'] = max(memory_samples)
summary['initial_pss_kib'] = memory_samples[0]
summary['first_settled_pss_kib'] = summary['memory'][0]['pss_kib']
summary['sampled_peak_above_first_settled_kib'] = max(memory_samples) - summary['first_settled_pss_kib']
refresh = environment['refresh_hz']
summary['frame_budget'] = {'refresh_hz': refresh if refresh > 0 else 60,
                           'reference_only': refresh <= 0}
for book in sorted({k[0] for k in groups}):
    selected = [v for k, v in groups.items() if k[0] == book]
    summary['books'][book] = {'samples': sum(len(g) for g in selected),
                             'worst_group_p95_ms': max(p95([r['us'] for r in g]) for g in selected) / 1000,
                             'worst_work_p95_ms': max(p95([r['work_us'] for r in g]) for g in selected) / 1000,
                             'max_batch_ms': max(r['max_batch_us'] for g in selected for r in g) / 1000}
for scenario in {r['scenario'] for r in rows if r['kind'] == 'stress_layout'}:
    selected = [r for r in rows if r['kind'] == 'stress_layout' and r['scenario'] == scenario]
    summary['stress'][scenario] = {**stats([r['us'] for r in selected]),
                                 'max_batch_ms': max(r['max_batch_us'] for r in selected) / 1000}
for state in ['cold', 'hot']:
    selected = [r for r in rows if r['kind'] == 'frame' and r['state'] == state]
    if selected:
        budget = 1e6 / summary['frame_budget']['refresh_hz']
        summary['frames'][state] = {'build': stats([r['build_us'] for r in selected]),
                                   'raster': stats([r['raster_us'] for r in selected]),
                                   'over_budget_percent': 100 * sum(r['build_us'] > budget or r['raster_us'] > budget for r in selected) / len(selected)}
(HERE / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
