import importlib.util,json,re,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('coverage_tool',root/'tool/coverage.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
lines={}
for package in ['packages/mm_design','packages/mm_pdf','apps/marginmind']:
 names=['evidence.info'] if package=='apps/marginmind' else ['lcov.info']
 for name in names:
  report=root/package/'coverage'/name
  if not report.exists(): continue
  report_lines=mod.merge([(package,report)],root)
  for key,hits in report_lines.items():
   lines[key]=lines.get(key,0)+hits
diff=subprocess.check_output(['git','diff',subprocess.check_output(['git','merge-base','HEAD','origin/main'],cwd=root,text=True).strip(),'--unified=0','--','apps','packages'],cwd=root,text=True)
changes={};source=None;number=0
for line in diff.splitlines():
 if line.startswith('+++ b/'):
  source=line[6:];changes[source]=set()
 elif line.startswith('@@'):
  number=int(re.search(r'\+(\d+)',line).group(1))
 elif line.startswith('+') and not line.startswith('+++'):
  changes[source].add(number);number+=1
 elif not line.startswith('-'):
  number+=1
rows=[];total=covered=0
for source,added in changes.items():
 if '/lib/' not in source or not source.endswith('.dart'): continue
 executable={n:lines[(source,n)] for n in added if (source,n) in lines}
 if not executable: continue
 hits=sum(h>0 for h in executable.values());count=len(executable)
 total+=count;covered+=hits
 missing=[n for n,h in executable.items() if not h]
 rows.append({'file':source,'covered':hits,'lines':count,'percent':round(hits/count*100,2),'missing':sorted(missing)})
result={'covered':covered,'lines':total,'percent':round(covered/total*100,2),'files':rows}
(root/'docs/evidence/gul-632/changed-coverage.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
