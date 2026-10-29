"""Summarize raw profile observations without excluding slow chapters."""
import gzip
import csv
import json
import math
import re
from collections import defaultdict, Counter
from pathlib import Path

here=Path(__file__).resolve().parent
records=[json.loads(l) for l in gzip.decompress((here/'android.jsonl.gz').read_bytes()).decode().splitlines()]
assert any(r['kind']=='done' for r in records), 'Incomplete run'
assert next(r for r in records if r['kind']=='environment')['profile'], 'Not a profile run'
def percentile(values,p):
    return sorted(values)[max(0,math.ceil(len(values)*p)-1)]
groups=defaultdict(list)
for r in records:
    if r['kind']=='layout': groups[(r['book'],r['chapter'],r['width'],r['font'])].append(r)
with (here/'chapters.csv').open('w') as f:
    writer=csv.writer(f, lineterminator='\n');writer.writerow(['book','chapter','width','font','utf16','blocks','images','tables','samples','p50_ms','p95_ms','max_ms','anchor_ok'])
    for key,rows in sorted(groups.items()):
        times=[r['us']/1000 for r in rows];r=rows[0]
        writer.writerow([*key,r['utf16'],r['blocks'],r['images'],r['tables'],len(rows),percentile(times,.5),percentile(times,.95),max(times),all(r['anchor_ok'] for r in rows)])
summary={}
for book in ['7337','33283','28885']:
    layouts=[r for r in records if r['kind']=='layout' and r['book']==book]
    frames=[r for r in records if r['kind']=='frame' and r['book']==book]
    worst=max((percentile([r['us']/1000 for r in rows],.95),key) for key,rows in groups.items() if key[0]==book)
    refresh=next(r['refresh_hz'] for r in records if r['kind']=='environment')
    budget=1000000/refresh
    summary[book]={'layout_samples':len(layouts),'worst_chapter_p95_ms':worst[0],'worst_key':worst[1],
      'anchor_failures':sum(not r['anchor_ok'] for r in layouts),'frames':len(frames),
      'build_p95_ms':percentile([r['build_us']/1000 for r in frames],.95),
      'raster_p95_ms':percentile([r['raster_us']/1000 for r in frames],.95),
      'over_budget_percent':100*sum(r['build_us']>budget or r['raster_us']>budget for r in frames)/len(frames)}
summary['events']=dict(Counter(r['kind'] for r in records))
mem=(here/'android-memory.txt').read_text()
pss=[int(n) for n in re.findall(r'TOTAL PSS:\s+(\d+)',mem)]
summary['memory']={'sample_count':len(pss),'first_pss_kib':pss[0] if pss else None,'peak_pss_kib':max(pss) if pss else None,'last_pss_kib':pss[-1] if pss else None}
(here/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
