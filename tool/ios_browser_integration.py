#!/usr/bin/env python3
"""Run iOS browser integration on a fresh simulator with bounded subprocesses."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/ios-browser-integration'


def run(command, *, timeout, log, cwd=ROOT):
    print(f'Running (limit {timeout}s): {" ".join(command)}', flush=True)
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            # Flutter can be waiting in simctl or a VM-service log reader.
            # Killing only the parent would leave those children running.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass  # The process group exited just as the deadline elapsed.
            except PermissionError:
                # macOS rejected a group signal for timed-out simctl in CI.
                # Reap our child; main's finally shuts down its device.
                process.kill()
            process.wait(timeout=10)
            raise
    result = log.read_text()
    if code:
        print(result, flush=True)
        raise subprocess.CalledProcessError(code, command)
    return result


def select_device(devices):
    candidates = [(runtime, device) for runtime, entries in devices.items()
                  if re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+', runtime)
                  for device in entries if device.get('isAvailable') and device['name'].startswith('iPhone')]
    if not candidates:
        raise ValueError('No available iPhone simulator runtime')
    # Dictionary order from simctl is not a device-selection policy. Use the
    # newest installed iOS and a stable model within it, then create our own UDID.
    latest = max((runtime for runtime, _ in candidates),
                 key=lambda value: tuple(int(part) for part in value.rsplit('iOS-', 1)[1].split('-')))
    device = min((device for runtime, device in candidates if runtime == latest), key=lambda item: item['name'])
    return latest, device['deviceTypeIdentifier']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    device_id = None

    def execute(name, command, timeout=30, cwd=ROOT):
        return run(command, timeout=timeout, log=OUT / f'{name}.log', cwd=cwd)

    try:
        devices = json.loads(execute('devices', ['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
        runtime, model = select_device(devices['devices'])
        device_id = execute('create', ['xcrun', 'simctl', 'create', 'MarginMind CI', model, runtime]).strip()
        print(f'Selected {runtime} / {model}: {device_id}', flush=True)
        execute('boot', ['xcrun', 'simctl', 'boot', device_id], timeout=60)
        # Bring up the selected simulator's UI before Flutter installs/launches
        # the app, rather than relying on a headless boot of a preinstalled device.
        execute('simulator', ['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', device_id])
        # Cold iOS boot, including data migration, took 5m31s in CI. Allow headroom
        # for that work while keeping a finite boot deadline.
        execute('bootstatus', ['xcrun', 'simctl', 'bootstatus', device_id, '-b'], timeout=600)
        # The expanded conversion/PDF fixture allows five minutes for tests;
        # also allow time to build the harness and launch the native process.
        result = execute('flutter', ['flutter', 'test', 'integration_test/browser_test.dart',
                                    '-d', device_id, '--no-pub', '--reporter', 'expanded', '--verbose'],
                         timeout=900, cwd=ROOT / 'apps/marginmind')
        print(result, flush=True)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'iOS browser integration failed: {error}; logs: {OUT}', flush=True)
        if device_id:
            for name, command in [
                ('state', ['xcrun', 'simctl', 'list', 'devices', '--json']),
                ('system', ['xcrun', 'simctl', 'spawn', device_id, 'log', 'show', '--last', '5m',
                            '--style', 'compact', '--predicate',
                            'process == "Runner" OR process == "SpringBoard"']),
            ]:
                try:
                    execute(name, command)
                except (OSError, subprocess.SubprocessError) as diagnostic_error:
                    print(f'Diagnostic {name} failed: {diagnostic_error}', flush=True)
        return 1
    finally:
        if device_id:
            for action in ['shutdown', 'delete']:
                try:
                    execute(action, ['xcrun', 'simctl', action, device_id], timeout=30)
                except (OSError, subprocess.SubprocessError) as error:
                    print(f'Simulator {action} failed: {error}', flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
