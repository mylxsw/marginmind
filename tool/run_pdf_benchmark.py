"""Run a macOS Release PDF benchmark and record its visible window.

Usage: python3 tool/run_pdf_benchmark.py before|after [--source app.bundle]
Requires ffmpeg, Accessibility and Screen Recording permissions. Keep the
benchmark window visible; a recording with occlusion is not valid evidence.
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
parser.add_argument('name', choices=['before', 'after'])
parser.add_argument('--source', type=pathlib.Path, default=root / 'apps/marginmind/build/macos/Build/Products/Release/Foliarc.app')
args = parser.parse_args()
name = args.name
out = root / 'performance-artifacts'
out.mkdir(exist_ok=True)
(out / f'{name}.json').unlink(missing_ok=True)
bundle = out / f'GUL495-{name}.app'
if args.source.resolve() == bundle.resolve():
    parser.error('--source must differ from the output bundle')
if bundle.exists():
    shutil.rmtree(bundle)
shutil.copytree(args.source, bundle, symlinks=True)
# Preserve the sandbox identifier and entitlements. Distinct executable names
# prevent activation from targeting another running Foliarc instance.
plist = bundle / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
executable = 'GUL495PDFBenchmark'
original = bundle / 'Contents/MacOS' / info['CFBundleExecutable']
if original.name != executable:
    original.rename(original.with_name(executable))
info.update(CFBundleExecutable=executable, CFBundleName=executable)
plist.write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--preserve-metadata=entitlements', str(bundle)], check=True)
with (out / f'{name}.log').open('w') as log, (out / f'{name}-record.log').open('w') as record_log:
    process = subprocess.Popen([str(bundle / 'Contents/MacOS' / executable)], stdout=log, stderr=subprocess.STDOUT)
    (out / f'{name}.pid').write_text(str(process.pid))
    capture = None
    try:
        time.sleep(2)
        region = subprocess.check_output(['swift', str(root / 'tool/pdf_benchmark_window.swift'), str(process.pid)], text=True).strip()
        x, y, width, height = map(int, region.split(','))
        capture = subprocess.Popen([
            'ffmpeg', '-hide_banner', '-y', '-f', 'avfoundation', '-framerate', '60', '-i', '0:none',
            '-t', '145', '-vf', f'crop={width}:{height}:{x}:{y},scale=1000:-2',
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '22', '-pix_fmt', 'yuv420p',
            str(out / f'{name}.mp4'),
        ], stdin=subprocess.PIPE, stdout=record_log, stderr=subprocess.STDOUT)
        process.wait(timeout=150)
        if process.returncode:
            raise RuntimeError(f'benchmark exited {process.returncode}')
        if capture.poll() is None:
            capture.communicate(b'q', timeout=15)
        if capture.returncode:
            raise RuntimeError(f'capture exited {capture.returncode}')
    finally:
        for child in [process, capture]:
            if child is not None and child.poll() is None:
                child.terminate()
                child.wait(timeout=10)
data = json.loads((out / f'{name}.log').read_text().split('PDF_BENCHMARK_JSON=')[1])
(out / f'{name}.json').write_text(json.dumps(data, indent=2))
for scenario, result in data.items():
    if 'ui' not in result:
        print(scenario, result)
        continue
    print(scenario, 'UI', result['ui']['p95_ms'], 'raster', result['raster']['p95_ms'], 'total', result['total']['p95_ms'])
