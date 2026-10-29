"""Run the release probe in the foreground, saving JSONL and settled Linux PSS.

Build first. On headless hosts: xvfb-run -a python3 docs/evidence/gul-572/run_linux.py
The child is always reaped, including on timeout/error. No persistent service.
"""
import gzip
import json
import os
from pathlib import Path
import platform
import selectors
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BUNDLE = ROOT / 'packages/mm_reflow/example/build/linux/arm64/release/bundle'
if not BUNDLE.exists():
    BUNDLE = ROOT / 'packages/mm_reflow/example/build/linux/x64/release/bundle'


def pss(pid):
    values = {}
    for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines():
        if line.startswith(('Pss:', 'Rss:')):
            name, amount, _ = line.split()
            values[name.rstrip(':').lower() + '_kib'] = int(amount)
    return values


def main():
    rows = []
    process = subprocess.Popen([str(BUNDLE / 'reflow_probe')], cwd=BUNDLE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               env={**os.environ, 'LIBGL_ALWAYS_SOFTWARE': '1'})
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + 1800
    buffer = b''
    done = False
    current_book = None
    sampled_at = 0.0
    log = (HERE / 'linux-stderr.log').open('wb')
    rows.append({'kind': 'host', 'system': platform.platform(), 'cpu_count': os.cpu_count(),
                 'rendering': 'Xvfb / Mesa software rasterizer', 'pid': process.pid})
    try:
        while time.monotonic() < deadline:
            if time.monotonic() - sampled_at >= 1:
                rows.append({'kind': 'memory_poll', 'book': current_book, **pss(process.pid)})
                sampled_at = time.monotonic()
            for key, _ in selector.select(timeout=1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    raise RuntimeError(f'Probe exited before done ({process.poll()})')
                buffer += chunk
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if b'REFLOW ' not in line:
                        log.write(line + b'\n')
                        continue
                    row = json.loads(line.split(b'REFLOW ', 1)[1])
                    rows.append(row)
                    if row['kind'] == 'book':
                        current_book = row['id']
                    if row['kind'] in ('book', 'book_done', 'memory_round', 'done', 'error'):
                        print(json.dumps(row), flush=True)
                    if row['kind'] == 'memory_round':
                        rows.append({**row, 'kind': 'memory', 'book': current_book, **pss(process.pid)})
                    if row['kind'] == 'error':
                        raise RuntimeError(row['error'])
                    if row['kind'] == 'done':
                        done = True
            if done:
                break
        if not done:
            raise TimeoutError('Probe did not finish in 30 minutes')
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()
        log.close()
        with gzip.open(HERE / 'linux.jsonl.gz', 'wt') as output:
            output.write(''.join(json.dumps(row) + '\n' for row in rows))
    if not done:
        raise RuntimeError('Incomplete benchmark')


if __name__ == '__main__':
    main()
