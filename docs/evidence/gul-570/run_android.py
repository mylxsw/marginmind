"""Run installed profile harness; collect JSONL and PSS until done or failure."""
import json
import selectors
import os
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = 'com.example.reflow_probe'
def adb(*args):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *args], text=True)
adb('shell','am','force-stop',PKG)
adb('logcat','-c')
proc = subprocess.Popen(['adb','-s','emulator-5554','logcat','-v','brief','flutter:I','*:S'],stdout=subprocess.PIPE,text=True)
selector = selectors.DefaultSelector()
selector.register(proc.stdout,selectors.EVENT_READ)
started = time.monotonic()
last_memory = 0
buffer = ''
try:
    adb('shell','am','start','-n',f'{PKG}/.MainActivity')
    with (HERE/'android.jsonl').open('w') as out, (HERE/'android-memory.txt').open('w') as mem:
        while time.monotonic()-started < 900:
            if time.monotonic()-last_memory > 5:
                mem.write(f'elapsed={time.monotonic()-started:.3f}\n')
                mem.write(adb('shell','dumpsys','meminfo',PKG))
                mem.flush()
                last_memory=time.monotonic()
            for key,_ in selector.select(timeout=1):
                buffer += os.read(key.fileobj.fileno(), 65536).decode('utf-8', errors='replace')
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if 'REFLOW ' not in line: continue
                    payload=line.split('REFLOW ',1)[1].strip()
                    value=json.loads(payload)
                    out.write(payload+'\n');out.flush()
                    if value['kind'] in ('book','book_done','done','error'): print(payload,flush=True)
                    if value['kind']=='error': raise RuntimeError(payload)
                    if value['kind']=='done': raise SystemExit(0)
        raise TimeoutError('Harness did not complete within 900 seconds')
finally:
    proc.terminate();proc.wait(timeout=10)
