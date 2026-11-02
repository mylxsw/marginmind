#!/usr/bin/env python3
"""Build a standalone UIKit reference app and capture native presentation states.

No Foliarc application code or data is used. Detent changes during capture are
programmatic; these screenshots do not constitute a manual gesture test.
"""
import argparse
import json
import plistlib
from pathlib import Path
import subprocess
import tempfile
import time


def run(*args):
    return subprocess.check_output(list(args), text=True, stderr=subprocess.STDOUT).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device', help='An iOS 26+ arm64 simulator UDID')
    parser.add_argument('--capture', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    source = Path(__file__).with_name('NativeSheetReference.swift')
    folder = Path(tempfile.mkdtemp(prefix='foliarc-native-sheet-reference-'))
    app = folder / 'NativeSheetReference.app'
    app.mkdir()
    sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path')
    print('Compiling UIKit reference', flush=True)
    print(run('xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-parse-as-library',
              '-swift-version', '5', '-module-name', 'FoliarcNativeSheetReference',
              '-sdk', sdk, '-target', 'arm64-apple-ios26.0-simulator',
              str(source), '-o', str(app / 'NativeSheetReference')), flush=True)
    bundle = 'io.github.mylxsw.foliarc.native-sheet-reference'
    info = {
        'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'NativeSheetReference',
        'CFBundleName': 'NativeSheetReference', 'CFBundleDisplayName': '原生面板参考',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
        'MinimumOSVersion': '26.0', 'UIDeviceFamily': [1],
        'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
        'UIApplicationSceneManifest': {
            'UIApplicationSupportsMultipleScenes': False,
            'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [
                {'UISceneConfigurationName': 'Reference'}]}},
        }
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--sign', '-', str(app))
    run('xcrun', 'simctl', 'bootstatus', args.device, '-b')
    run('xcrun', 'simctl', 'install', args.device, str(app))
    print(run('xcrun', 'simctl', 'launch', '--terminate-running-process', args.device, bundle), flush=True)
    time.sleep(2)
    container = Path(run('xcrun', 'simctl', 'get_app_container', args.device, bundle, 'data'))
    cache = container / 'Library/Caches'
    cache.mkdir(parents=True, exist_ok=True)
    command, ack = cache / 'native-sheet-reference-command.txt', cache / 'native-sheet-reference-ack.txt'
    def mode(value):
        ack.unlink(missing_ok=True)
        temporary = command.with_suffix('.tmp')
        temporary.write_text(value)
        temporary.replace(command)
        deadline = time.monotonic() + 10
        while not ack.exists() or ack.read_text() != value:
            if time.monotonic() > deadline:
                raise TimeoutError('Reference app did not accept fixture command: ' + value)
            time.sleep(0.1)
    if args.capture:
        out = root / 'docs/evidence/ios-native-sheet-reference-2026-11-02'
        out.mkdir(parents=True, exist_ok=True)
        run('xcrun', 'simctl', 'ui', args.device, 'appearance', 'light')
        for name, value in [('01-medium', 'medium'), ('02-large', 'large'), ('03-keyboard', 'keyboard')]:
            mode(value)
            time.sleep(2)
            run('xcrun', 'simctl', 'io', args.device, 'screenshot', str(out / (name + '.png')))
            print('Captured', name, flush=True)
        run('xcrun', 'simctl', 'ui', args.device, 'appearance', 'dark')
        mode('medium')
        time.sleep(2)
        run('xcrun', 'simctl', 'io', args.device, 'screenshot', str(out / '04-medium-dark.png'))
        mode('confirm')
        time.sleep(2)
        run('xcrun', 'simctl', 'io', args.device, 'screenshot', str(out / '05-unsaved-confirmation.png'))
        (out / 'capture.json').write_text(json.dumps({
            'device': args.device, 'bundle_id': bundle,
            'source': str(source.relative_to(root)),
            'sdk': sdk, 'detent_changes': 'programmatic',
            'scope': 'standalone UIKit reference; no Flutter integration or Foliarc business data',
        }, ensure_ascii=False, indent=2))
        run('xcrun', 'simctl', 'ui', args.device, 'appearance', 'light')
        mode('reset')
        print('Native reference screenshots:', out, flush=True)
    print('Temporary build:', app, flush=True)


if __name__ == '__main__':
    main()
