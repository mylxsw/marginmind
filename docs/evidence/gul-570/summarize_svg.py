"""Summarize the SVG follow-up without discarding slow chapters or frames."""
import gzip
import csv
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path
here = Path(__file__).resolve().parent
rows = [json.loads(x) for x in gzip.decompress((here/'svg-android.jsonl.gz').read_bytes()).decode().splitlines()]
assert rows[-1]['kind'] == 'done'
env = next(r for r in rows if r['kind'] == 'environment')
assert env['profile'] and env['repeats'] == 30

def p95(values):
    return sorted(values)[math.ceil(len(values)*.95)-1]

groups = defaultdict(list)
for r in rows:
    if r['kind'] == 'layout': groups[(r['chapter'], r['width'], r['font'])].append(r)
with (here/'svg-chapters.csv').open('w') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow(['chapter', 'width', 'font', 'samples', 'p95_ms', 'max_ms', 'anchor_ok'])
    for key, values in sorted(groups.items()):
        us = [r['us']/1000 for r in values]
        w.writerow([*key, len(us), p95(us), max(us), all(r['anchor_ok'] for r in values)])
summary = {'events': dict(Counter(r['kind'] for r in rows)),
           'worst_layout_p95_ms': max(p95([r['us']/1000 for r in g]) for g in groups.values()),
           'anchor_failures': sum(not r['anchor_ok'] for g in groups.values() for r in g),
           'frames': {}, 'decode_and_first_layout': {}}
for state in ['cold', 'hot']:
    frames = [r for r in rows if r['kind'] == 'frame' and r['state'] == state]
    budget = 1e6/env['refresh_hz']
    over = sum(r['build_us'] > budget or r['raster_us'] > budget for r in frames)
    summary['frames'][state] = {'count': len(frames), 'over': over, 'over_percent': over*100/len(frames),
        'build_p95_ms': p95([r['build_us']/1000 for r in frames]),
        'raster_p95_ms': p95([r['raster_us']/1000 for r in frames])}
    decode = [r['us']/1000 for r in rows if r['kind'] == 'decode' and r['state'] == state]
    summary['decode_and_first_layout'][state] = {'count':len(decode), 'p95_ms':p95(decode), 'max_ms':max(decode)}
mem = (here/'svg-android-memory.txt').read_text()
summary['memory_rounds'] = [{'round': int(r), 'switches': int(s), 'pss_kib': int(p)} for r,s,p in re.findall(r'round=(\d+) switches=(\d+).*?TOTAL PSS:\s+(\d+)', mem, re.S)]
summary['unsupported_paths'] = sorted({r['path'] for r in rows if r['kind'] in ('unsupported_image','missing_image')})
(here/'svg-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
