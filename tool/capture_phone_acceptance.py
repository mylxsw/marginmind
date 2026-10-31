#!/usr/bin/env python3
"""Capture 10 mobile redesign scenes on iOS Simulator for GUL-629/GUL-635 acceptance."""

import os
from pathlib import Path
import re
import subprocess
import sys
import time

DEVICE = '5955CB86-1516-4567-A272-EE131D12120A'


def main():
    device = sys.argv[1] if len(sys.argv) > 1 else DEVICE
    root = Path(__file__).resolve().parents[1]
    out_dir = root / 'docs/evidence/gul-629'
    out_dir.mkdir(parents=True, exist_ok=True)

    env = dict(os.environ)
    env['PATH'] = f'/tmp/bin_override:{env.get("PATH", "")}'

    # Clean status bar
    subprocess.run(
        [
            'xcrun',
            'simctl',
            'status_bar',
            device,
            'override',
            '--time',
            '9:41',
            '--batteryState',
            'charged',
            '--batteryLevel',
            '100',
            '--wifiBars',
            '3',
            '--cellularBars',
            '4',
        ],
        env=env,
        check=True,
    )

    cmd = [
        'flutter',
        'test',
        'integration_test/phone_gul629_acceptance_test.dart',
        '-d',
        device,
        '--no-pub',
        '--reporter',
        'expanded',
    ]

    print(f'Starting test run on device {device}...')
    proc = subprocess.Popen(
        cmd,
        cwd=root / 'apps/marginmind',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )

    captured = []
    try:
        for line in proc.stdout:
            print(line, end='', flush=True)
            match = re.search(r'PHONE_SHOT:([\w-]+):(.+)', line)
            if not match:
                continue

            name = match.group(1)
            marker_path = match.group(2).strip()

            # Adjust simulator system appearance to match screenshot
            if name.endswith('dark'):
                subprocess.run(['xcrun', 'simctl', 'ui', device, 'appearance', 'dark'], env=env, check=True)
            else:
                subprocess.run(['xcrun', 'simctl', 'ui', device, 'appearance', 'light'], env=env, check=True)

            time.sleep(0.35)

            target = out_dir / f'{name}.png'
            print(f'--> Capturing {name} to {target}...')
            subprocess.run(
                ['xcrun', 'simctl', 'io', device, 'screenshot', str(target)],
                env=env,
                check=True,
                capture_output=True,
                timeout=20,
            )
            captured.append(name)

            # Signal Flutter test to proceed
            Path(marker_path).write_text(f'captured:{name}')

        ret = proc.wait(timeout=60)
        print(f'Test finished with exit code {ret}. Total captured: {len(captured)}')
        return ret
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=15)


if __name__ == '__main__':
    raise SystemExit(main())
