#!/usr/bin/env python3
"""Capture the export sheet from the real app, one screenshot per state.

Usage (from the repository root, on a Mac):
  python3 tool/capture_document_export.py macos OUT_DIR [--dark] [--real-save]
  python3 tool/capture_document_export.py SIMULATOR_UDID OUT_DIR [--dark] [--real-save]
  python3 tool/capture_document_export.py emulator-5554 OUT_DIR [--dark]
"""
import argparse
from pathlib import Path
import re
import subprocess

WINDOW_ID = '''import Cocoa
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
var best = (0, 0.0)
for w in windows where (w[kCGWindowOwnerName as String] as? String)?.contains("oliarc") == true || (w[kCGWindowOwnerName as String] as? String) == "marginmind" {
  let b = w[kCGWindowBounds as String] as! [String: Double]
  let area = b["Width"]! * b["Height"]!
  if (w[kCGWindowLayer as String] as? Int) == 0 && area > best.1 { best = (w[kCGWindowNumber as String] as! Int, area) }
}
print(best.0)
'''


def capture(device, path):
    if device == 'macos':
        window = subprocess.run(['swift', '-e', WINDOW_ID], check=True, capture_output=True, text=True).stdout.strip()
        subprocess.run(['screencapture', '-x', '-o', '-l', window, str(path)], check=True, timeout=20)
    elif device.startswith('emulator-'):
        with path.open('wb') as out:
            subprocess.run(['adb', '-s', device, 'exec-out', 'screencap', '-p'], check=True, stdout=out, timeout=20)
    else:
        subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(path)], check=True, capture_output=True, timeout=20)


def acknowledge(device, marker, name):
    if device.startswith('emulator-'):
        subprocess.run(['adb', '-s', device, 'shell', f"run-as io.github.mylxsw.marginmind sh -c 'echo -n captured:{name} > {marker}'"], check=True, timeout=20)
    else:
        Path(marker).write_text('captured:' + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('out', type=Path)
    parser.add_argument('--dark', action='store_true')
    parser.add_argument('--real-save', action='store_true')
    parser.add_argument('--native-menu', action='store_true', help='iPhone only: stop at the native More sheet')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    args.out.mkdir(parents=True, exist_ok=True)
    command = ['flutter', 'test', 'integration_test/document_export_screens_test.dart', '-d', args.device,
               '--no-pub', '--dart-define=CAPTURE_UI=true', '--reporter', 'expanded']
    if args.dark:
        command.append('--dart-define=UI_DARK=true')
    if args.real_save:
        command.append('--dart-define=UI_REAL_SAVE=true')
    if args.native_menu:
        command.append('--dart-define=UI_NATIVE_MENU=true')
    process = subprocess.Popen(command, cwd=root / 'apps/marginmind', stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    try:
        for line in process.stdout:
            print(line, end='', flush=True)
            match = re.search(r'PHONE_SHOT:([\w-]+):(.+)', line)
            if match:
                capture(args.device, args.out / (match[1] + '.png'))
                acknowledge(args.device, match[2].strip(), match[1])
                if match[1] == '12-native-more':
                    subprocess.run(['rm', '-rf', str(args.out / 'native-menu.xcresult')])
                    subprocess.run(['ruby', str(root / 'tool/ios_ui_tests/run.rb'), args.device,
                                    str(args.out / 'native-menu.xcresult'),
                                    'IntegrationNativePresentationTests/testExportCopyRow'], check=True)
        return process.wait(timeout=30)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=15)


if __name__ == '__main__':
    raise SystemExit(main())
