#!/usr/bin/env python3
"""Run the macOS study-note integration test and capture only its native window.

The host captures screenshots because the application's sandbox cannot launch
xcrun/Swift or write arbitrary evidence paths. The app sends a local HTTP request
at each settled frame; no application entitlements are changed.
"""
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import subprocess
import threading
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
NAMES = {'note-light', 'note-dark', 'export-light', 'export-dark'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evidence/gul-588')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    captured = set()

    class Capture(BaseHTTPRequestHandler):
        def do_GET(self):
            try:
                url = urlparse(self.path)
                name = url.path.removeprefix('/capture/')
                pid = parse_qs(url.query).get('pid', [''])[0]
                if name not in NAMES or not pid.isdecimal():
                    raise ValueError('Invalid capture request')
                script = '''import Cocoa
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in windows where (w[kCGWindowOwnerPID as String] as? Int) == TARGET_PID && (w[kCGWindowLayer as String] as? Int) == 0 {
  print(w[kCGWindowNumber as String]!); break
}
'''.replace('TARGET_PID', pid)
                window = subprocess.run(['/usr/bin/swift', '-e', script], check=True, capture_output=True, text=True, timeout=30).stdout.strip()
                if not window.isdecimal():
                    raise ValueError('No native application window')
                subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', window, str(args.output / f'{name}.png')], check=True, timeout=15)
                captured.add(name)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'captured')
            except Exception as error:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(error).encode())

        def log_message(self, *_):
            pass

    server = HTTPServer(('127.0.0.1', 0), Capture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(['flutter', 'test', 'integration_test/study_notes_test.dart', '-d', 'macos', '--no-pub',
            f'--dart-define=GUL588_SHOT_SERVER=http://127.0.0.1:{server.server_port}'], cwd=ROOT / 'apps/marginmind')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    if result.returncode:
        raise SystemExit(result.returncode)
    if captured != NAMES:
        raise SystemExit(f'Missing screenshots: {sorted(NAMES - captured)}')
    print('Captured:', ', '.join(sorted(captured)))


if __name__ == '__main__':
    main()
