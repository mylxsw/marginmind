#!/usr/bin/env python3
"""Capture actual iOS Simulator or Android emulator screens with a per-screen acknowledgement.

Usage: python3 tool/capture_mobile_redesign.py DEVICE_UDID iphone [--reference]
Run only against a simulator fixture; Flutter installs a test build there.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('name', help='Evidence subfolder, e.g. iphone or ipad')
    parser.add_argument('--test', default='mobile_redesign_acceptance_test.dart')
    parser.add_argument('--reference', action='store_true', help='Core iPad reference screens only')
    parser.add_argument('--from-screen', default='', help='Resume capture from a screen prefix')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = root / 'docs/evidence/mobile-redesign-2026-11-02' / args.name
    out.mkdir(parents=True, exist_ok=True)
    source = hashlib.sha256()
    for directory in [root / 'apps/marginmind/lib', root / 'packages']:
        for file in sorted(directory.rglob('*.dart')):
            if 'lib' in file.parts:
                source.update(str(file.relative_to(root)).encode())
                source.update(file.read_bytes())
    (out / 'build-source.json').write_text(json.dumps({'device': args.device, 'test': args.test, 'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), 'dart_source_sha256': source.hexdigest()}, indent=2))
    command = ['flutter', 'test', 'integration_test/' + args.test, '-d', args.device,
               '--no-pub', '--dart-define=CAPTURE_PHONE_UI=true', '--reporter', 'expanded']
    if args.reference:
        command.append('--dart-define=MOBILE_UI_REFERENCE=true')
    if args.from_screen:
        command.append('--dart-define=MOBILE_UI_CAPTURE_FROM=' + args.from_screen)
    process = subprocess.Popen(command, cwd=root / 'apps/marginmind', stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    try:
        with (out / 'run.log').open('w') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line, end='', flush=True)
                match = re.search(r'PHONE_SHOT:([\w-]+):(.+)', line)
                if not match:
                    continue
                target = out / (match[1] + '.png')
                marker = match[2].strip()
                if args.device.startswith('emulator-'):
                    with target.open('wb') as screenshot:
                        subprocess.run(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'], stdout=screenshot, check=True, timeout=20)
                    subprocess.run(['adb', '-s', args.device, 'shell', 'run-as', 'io.github.mylxsw.marginmind', 'tee', marker], input=('captured:' + match[1]).encode(), check=True, capture_output=True, timeout=20)
                else:
                    subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot', str(target)], check=True, capture_output=True, timeout=20)
                    Path(marker).write_text('captured:' + match[1])
        return process.wait(timeout=30)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=15)


if __name__ == '__main__':
    raise SystemExit(main())
