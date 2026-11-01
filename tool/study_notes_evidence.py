#!/usr/bin/env python3
"""Run macOS study-note integration tests and capture visual evidence.

The host captures native windows for the original flows. The independent note
workspace uploads its rendered scene (including popup menus) over localhost.
The app sandbox and entitlements stay unchanged.
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
    parser.add_argument('--updates', action='store_true', help='Capture incremental updates and templates')
    parser.add_argument('--workspace', action='store_true', help='Capture the independent note workspace and its references')
    parser.add_argument('--ai', action='store_true', help='Capture the fake-organizer AI flow')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evidence/gul-588')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    names = {'outline', 'generating', 'ai-on', 'ai-off'} if args.ai else NAMES
    target = 'integration_test/study_notes_ai_test.dart' if args.ai else 'integration_test/study_notes_test.dart'
    if args.updates:
        names = {'update-banner', 'update-preview', 'update-applied', 'reading', 'cornell', 'review', 'review-dark'}
        target = 'integration_test/study_notes_updates_test.dart'
    if args.workspace:
        names = {'note-page-light', 'note-source-light', 'note-source-dark', 'note-map-dark', 'note-page-dark', 'note-menu-dark'}
        target = 'integration_test/note_workspace_test.dart'
    captured = set()

    class Capture(BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                name = urlparse(self.path).path.removeprefix('/capture/')
                length = int(self.headers.get('Content-Length', '0'))
                if not args.workspace or name not in names or not 0 < length <= 24 * 1024 * 1024:
                    raise ValueError('Invalid rendered capture request')
                data = self.rfile.read(length)
                if len(data) != length or not data.startswith(bytes.fromhex('89504e470d0a1a0a')):
                    raise ValueError('Invalid PNG')
                (args.output / f'{name}.png').write_bytes(data)
                captured.add(name)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'captured')
            except Exception as error:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(error).encode())

        def do_GET(self):
            try:
                url = urlparse(self.path)
                name = url.path.removeprefix('/capture/')
                pid = parse_qs(url.query).get('pid', [''])[0]
                if name not in names or not pid.isdecimal():
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
        result = subprocess.run(['flutter', 'test', target, '-d', 'macos', '--no-pub',
            f'--dart-define=GUL588_SHOT_SERVER=http://127.0.0.1:{server.server_port}'], cwd=ROOT / 'apps/marginmind')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    if result.returncode:
        raise SystemExit(result.returncode)
    if captured != names:
        raise SystemExit(f'Missing screenshots: {sorted(names - captured)}')
    print('Captured:', ', '.join(sorted(captured)))


if __name__ == '__main__':
    main()
