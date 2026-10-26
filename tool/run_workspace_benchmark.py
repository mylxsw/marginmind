"""Record a full Release workspace under native wheel input (macOS).

Build apps/marginmind/benchmark/workspace.dart first. Uses a private generated
library, never the user's library. Waits for all children and preserves raw data.
"""
import argparse
import json
import pathlib
import plistlib
import shutil
import subprocess
import time

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('name', choices=['workspace-before', 'workspace-after'])
parser.add_argument('--source', type=pathlib.Path, required=True)
args = parser.parse_args()
out = root / 'performance-artifacts'
bundle = out / f'{args.name}.app'
if args.source.resolve() == bundle.resolve():
    parser.error('source and output bundle must differ')
if bundle.exists():
    shutil.rmtree(bundle)
shutil.copytree(args.source, bundle, symlinks=True)
plist = bundle / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
executable = 'GUL495Workspace'
original = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
original.rename(original.with_name(executable))
info.update(CFBundleExecutable=executable, CFBundleName=executable)
plist.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--preserve-metadata=entitlements', str(bundle)], check=True)
subprocess.run(['swiftc', str(root / 'tool/workspace_wheel.swift'), '-o', str(out / 'workspace-wheel')], check=True)
log_path = out / f'{args.name}.log'
record = None
wheel = None
with log_path.open('w') as log, (out / f'{args.name}-record.log').open('w') as record_log:
    app = subprocess.Popen([str(bundle / 'Contents/MacOS' / executable)], stdout=log, stderr=subprocess.STDOUT)
    try:
        # An occluded macOS Flutter window can suspend its startup frame clock.
        time.sleep(2)
        subprocess.run(['swift', str(root / 'tool/pdf_benchmark_window.swift'), str(app.pid)], check=True, stdout=subprocess.DEVNULL)
        deadline = time.monotonic() + 50
        while 'WORKSPACE_READY' not in log_path.read_text():
            if app.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('workspace did not become ready: ' + log_path.read_text()[-2000:])
            time.sleep(.25)
        region = subprocess.check_output(['swift', str(root / 'tool/pdf_benchmark_window.swift'), str(app.pid)], text=True)
        x, y, width, height = map(int, region.strip().split(','))
        scale = float(subprocess.check_output(['swift', '-e', 'import AppKit; print(NSScreen.main!.backingScaleFactor)'], text=True))
        record = subprocess.Popen([
            'ffmpeg', '-hide_banner', '-y', '-f', 'avfoundation', '-framerate', '60', '-i', '0:none',
            '-vf', f'crop={width}:{height}:{x}:{y},scale=1600:-2',
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '26', '-pix_fmt', 'yuv420p',
            str(out / f'{args.name}.mp4'),
        ], stdin=subprocess.PIPE, stdout=record_log, stderr=subprocess.STDOUT)
        time.sleep(1)
        wheel = subprocess.Popen([str(out / 'workspace-wheel'), str(app.pid), str((x + width * .35) / scale), str((y + height * .5) / scale)])
        deadline = time.monotonic() + 55
        while 'WORKSPACE_TIMINGS_JSON=' not in log_path.read_text():
            if app.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError('no measured input/result: ' + log_path.read_text()[-2000:])
            time.sleep(.2)
        record.communicate(b'q', timeout=15)
        wheel.wait(timeout=5)
        app.wait(timeout=10)
        if any(child.returncode for child in (app, record, wheel)):
            raise RuntimeError('a child process failed')
    finally:
        for child in (wheel, record, app):
            if child is not None and child.poll() is None:
                child.terminate()
                child.wait(timeout=10)
line = next(line for line in log_path.read_text().splitlines() if line.startswith('WORKSPACE_TIMINGS_JSON='))
data = json.loads(line.split('=', 1)[1])
data.pop('physicalSize', None)  # Native geometry below is reliable in Release builds.
if len(data['events']) < 1000 or len(data['frames_us']) < 100:
    raise RuntimeError('insufficient delivered events or rendered frames')
for index, name in enumerate(['ui', 'raster', 'total']):
    values = sorted(f[index] / 1000 for f in data['frames_us'])
    data[name] = {f'p{p}_ms': values[min(len(values)-1, int((len(values)-1)*p/100))] for p in [50, 95, 99]}
data['native_window_pixels'] = [width, height]
(out / f'{args.name}.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
print(json.dumps({k: v for k, v in data.items() if k not in ['events', 'frames_us']}, indent=2))
