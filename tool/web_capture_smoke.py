"""Run live DOM/session/sanitization checks: python tool/web_capture_smoke.py --dart /path/to/dart --chromium /path/to/chromium."""
import argparse
import base64
import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--dart', default='dart')
parser.add_argument('--chromium')
args = parser.parse_args()
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVYsAAAAASUVORK5CYII=')
requests = []

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        if self.path == '/image.svg':
            self.send_response(200); self.send_header('Content-Type', 'image/svg+xml'); self.end_headers()
            self.wfile.write(b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" onload="SVG_SECRET()"><script>SVG_SECRET()</script><foreignObject>active</foreignObject><rect width="10" height="10" fill="red"/></svg>')
            return
        if self.path == '/image.png':
            if 'reader=1' not in self.headers.get('Cookie', ''):
                self.send_response(403); self.end_headers(); return
            self.send_response(200); self.send_header('Content-Type', 'image/png'); self.end_headers()
            self.wfile.write(png)
            return
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers()
        paragraphs = ''.join('<p>Canonical paragraph %s, about spaced repetition, practice, and retention. '
                             'The browser renders this article for an authenticated reader.</p>' % i for i in range(25))
        self.wfile.write(('''<!doctype html><title>Session article</title><style>.hidden{display:none}</style>
            <script>document.cookie='reader=1';setTimeout(()=>document.querySelector('article').insertAdjacentHTML('beforeend',
            '<p>Live DOM after loading</p>'),25)</script><nav>Site navigation</nav><form><article><h1>Article</h1>'''
            + paragraphs + '''<img src='/image.png'><img src='/image.svg'><p class='hidden'>HIDDEN_SECRET</p></article></form>
            <form><input value='FORM_SECRET'><textarea>FORM_SECRET</textarea></form>
            <script>SCRIPT_SECRET='secret'</script>''').encode())
    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=args.chromium, headless=True, args=['--no-sandbox'])
        page = browser.new_page(viewport={'width': 800, 'height': 600})
        page.goto('http://127.0.0.1:%s/page' % server.server_port)
        page.wait_for_timeout(100)
        for original in (False, True):
            page.evaluate('scrollTo(0,150)')
            script = subprocess.check_output([args.dart, 'run', 'packages/mm_platform/tool/web_capture_script.dart'] +
                                             (['--original'] if original else []), text=True)
            page.evaluate(script)
            page.wait_for_function('globalThis.testCapture.result', timeout=45000)
            result = page.evaluate('globalThis.testCapture.result')
            assert 'error' not in result, result
            assert result['title'] == 'Session article'
            assert 'Live DOM after loading' in result['html']
            assert 'FORM_SECRET' not in result['snapshot']
            assert 'SCRIPT_SECRET' not in result['snapshot']
            assert 'HIDDEN_SECRET' not in result['snapshot']
            assert '<script' not in result['snapshot']
            assert 'Content-Security-Policy' in result['snapshot']
            assert base64.b64decode(next(iter(result['resources'].values()))) == png
            svg = base64.b64decode(next(v for k,v in result['resources'].items() if k.endswith('.svg')))
            assert b'SVG_SECRET' not in svg and b'foreignObject' not in svg and b'<rect' in svg
            assert 'resources/image-1.png' in result['html']
            if original:
                page.evaluate('globalThis.testCapture.preparePrint()')
                page.emulate_media(media='print')
                assert page.locator('nav').is_hidden()
                host = page.locator('#testCapture_print')
                assert host.is_visible()
                assert host.bounding_box()['width'] <= 800
                page.emulate_media(media='screen')
                assert host.is_hidden()
                assert page.locator('nav').is_visible()
                page.evaluate('globalThis.testCapture.cancel()')
                assert page.locator('#testCapture_print').count() == 0
            assert page.evaluate('scrollY') == 150
            assert requests.count('/page') == 1, requests
        page.evaluate(script)
        page.wait_for_timeout(50)
        page.evaluate("history.pushState({},'', '/spa');scrollTo(0,0)")
        page.wait_for_function('globalThis.testCapture.result', timeout=5000)
        assert 'error' in page.evaluate('globalThis.testCapture.result')
        assert page.evaluate('scrollY') == 0, 'A stale capture must not scroll the new SPA route'
        # A fetch that never returns must lose only its image, even when a
        # healthy image follows it in the same capture.
        hanging = []
        page.route('**/hang.png', lambda route: hanging.append(route))
        page.evaluate("""document.querySelector('article').insertAdjacentHTML('afterbegin',
            '<img src="/hang.png">')""")
        readable = subprocess.check_output([args.dart, 'run', 'packages/mm_platform/tool/web_capture_script.dart'], text=True)
        page.evaluate(readable)
        page.wait_for_function('globalThis.testCapture.result', timeout=45000)
        result = page.evaluate('globalThis.testCapture.result')
        assert 'error' not in result, result
        assert 'image_unavailable' in result['diagnostics'], result
        assert any(k.endswith('.png') for k in result['resources']), result
        assert 'Canonical paragraph' in result['html']
        for route in hanging:
            route.abort()
        page.evaluate("document.querySelector('img[src=\"/hang.png\"]').remove()")
        # Exhaust the image budget after the first image without waiting 40s.
        # The rest must be omitted with diagnostics while the article survives.
        page.evaluate("""() => {
          globalThis.clockShift = 0;
          globalThis.realNow = performance.now.bind(performance);
          Object.defineProperty(performance, 'now', {configurable:true, value:()=>realNow()+clockShift});
          globalThis.realFetch = fetch;
          globalThis.fetch = async (...args) => {const response=await realFetch(...args);clockShift=41000;return response;};
        }""")
        page.evaluate(readable)
        page.wait_for_function('globalThis.testCapture.result', timeout=5000)
        result = page.evaluate('globalThis.testCapture.result')
        assert 'error' not in result, result
        assert 'image_unavailable' in result['diagnostics'], result
        assert len(result['resources']) == 1, result
        page.evaluate('fetch=realFetch;delete performance.now')
        browser.close()
    print(json.dumps({'live_dom': True, 'session_images': True, 'sanitized_snapshot': True,
                      'scroll_restored': True, 'slow_image_isolated': True, 'page_requests': requests.count('/page')}))
finally:
    server.shutdown(); server.server_close(); thread.join()
