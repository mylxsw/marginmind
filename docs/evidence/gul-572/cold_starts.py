"""Five fresh process launches through the first real chapter's completed layout.

This measures process startup + initial EPUB parse/decode/layout, not first paint.
OS filesystem caches are not flushed. Run under xvfb-run after the normal probe.
"""
import json
import os
import selectors
import subprocess
import time
from run_linux import BUNDLE, HERE, pss


def sample():
    started = time.monotonic_ns()
    process = subprocess.Popen([str(BUNDLE / 'reflow_probe')], cwd=BUNDLE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               env={**os.environ, 'LIBGL_ALWAYS_SOFTWARE': '1'})
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b''
    try:
        while time.monotonic_ns() - started < 90_000_000_000:
            for key, _ in selector.select(timeout=1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Probe ended before its initial chapter completed')
                buffer += chunk
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if b'REFLOW ' not in line:
                        continue
                    row = json.loads(line.split(b'REFLOW ', 1)[1])
                    if row['kind'] == 'error':
                        raise RuntimeError(row['error'])
                    if row['kind'] == 'environment':
                        return {'elapsed_us': (time.monotonic_ns() - started) // 1000,
                                'environment': row, **pss(process.pid)}
        raise TimeoutError('Initial chapter exceeded 90 seconds')
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()


if __name__ == '__main__':
    results = []
    for index in range(5):
        row = {'launch': index + 1, **sample()}
        results.append(row)
        print(json.dumps(row), flush=True)
    (HERE / 'cold-starts.json').write_text(json.dumps(results, indent=2) + '\n')
