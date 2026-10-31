#!/usr/bin/env python3
"""Capture actual iOS simulator screens with a per-screen acknowledgement.

Usage: python3 tool/capture_mobile_ui.py DEVICE_UDID iphone [--reference]
Run only against a simulator fixture; Flutter installs a test build there.
"""
import argparse
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('name', help='Evidence subfolder, e.g. iphone or ipad')
    parser.add_argument('--reference', action='store_true', help='Core iPad reference screens only')
    parser.add_argument('--from-screen', default='', help='Resume capture from a screen prefix')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = root / 'docs/evidence/phone-adaptation' / args.name
    out.mkdir(parents=True, exist_ok=True)
    command = ['flutter', 'test', 'integration_test/phone_adaptation_test.dart', '-d', args.device,
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
                subprocess.run(['xcrun', 'simctl', 'io', args.device, 'screenshot',
                                str(out / (match[1] + '.png'))], check=True, capture_output=True, timeout=20)
                Path(match[2].strip()).write_text('captured:' + match[1])
        return process.wait(timeout=30)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=15)


if __name__ == '__main__':
    raise SystemExit(main())
