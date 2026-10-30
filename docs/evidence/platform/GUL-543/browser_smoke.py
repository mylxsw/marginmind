#!/usr/bin/env python3
"""Run against `flutter build web --release`; requires playwright and Chrome.

Runs its own HTTP server and fresh browser context; both close before exit.
No sample data or test hooks are injected into the application.
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
from threading import Thread
from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
TITLE = 'Persistent browser node'


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def semantics(page):
    page.wait_for_function('document.querySelector("flt-semantics-placeholder") || document.querySelector("flt-semantics")')
    placeholder = page.locator('flt-semantics-placeholder')
    if placeholder.count():
        placeholder.evaluate('(element) => element.click()')


def library(page):
    return page.evaluate('''async () => {
      const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('marginmind-library');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      try {
        const tx = db.transaction('files');
        const store = tx.objectStore('files');
        const keys = await new Promise((resolve) => {store.getAllKeys().onsuccess = e => resolve(e.target.result)});
        return await Promise.all(keys.filter(k => k.endsWith('/studyset.json')).map(key =>
          new Promise(resolve => {store.get(key).onsuccess = e =>
            resolve(JSON.parse(new TextDecoder().decode(e.target.result)))})));
      } finally {db.close()}
    }''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chrome', default=os.environ.get('CHROME_EXECUTABLE') or shutil.which('google-chrome')
                        or '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(ROOT / 'apps/marginmind/build/web')))
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    errors = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(executable_path=args.chrome, headless=True)
            try:
                page = browser.new_page(viewport={'width': 1440, 'height': 1000}, locale='en-US')
                page.set_default_timeout(60000)
                expect.set_options(timeout=60000)
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' else None)
                page.goto(f'http://127.0.0.1:{server.server_port}')
                semantics(page)
                create = page.get_by_role('button', name='New Study Set', exact=True).first
                expect(create).to_be_visible()
                page.screenshot(path=str(OUT / '01-library.png'))
                with page.expect_file_chooser() as chooser:
                    create.click()
                chooser.value.set_files(str(ROOT / 'apps/marginmind/assets/sample/sample.pdf'))
                expect(page.get_by_role('group', name='Page 1', exact=True)).to_be_visible()
                root = page.get_by_role('button', name='sample', exact=True).last
                expect(root).to_be_visible()
                root.click(button='right', force=True)
                page.get_by_role('button', name='Add Child Topic', exact=True).last.click(force=True)
                field = page.locator('textarea:not([disabled])').last
                field.fill(TITLE)
                field.press('Enter')
                expect(page.get_by_role('button', name=TITLE, exact=True)).to_be_visible()
                # Wait for the repository's acknowledged transaction, not just its UI draft.
                page.wait_for_function('''async () => {
                  const db = await new Promise(r => {indexedDB.open('marginmind-library').onsuccess = e => r(e.target.result)});
                  const values = await new Promise(r => {db.transaction('files').objectStore('files').getAll().onsuccess = e => r(e.target.result)});
                  db.close();
                  return values.some(v => {try {const j=JSON.parse(new TextDecoder().decode(v));
                    return j.content?.cards?.some(c => c.title === 'Persistent browser node')}
                    catch (_) {return false}});
                }''')
                before = library(page)
                assert len(before) == 1 and len(before[0]['content']['documents']) == 1
                page.screenshot(path=str(OUT / '02-import-and-edit.png'))
                page.reload()
                semantics(page)
                page.get_by_role('button', name=re.compile('^sample Last read:')).dispatch_event('click')
                expect(page.get_by_role('button', name=TITLE, exact=True)).to_be_visible()
                expect(page.get_by_role('group', name='Page 1', exact=True)).to_be_visible()
                after = library(page)
                assert after[0]['content']['cards'] == before[0]['content']['cards']
                assert after[0]['content']['documents'][0]['fileName'] == before[0]['content']['documents'][0]['fileName']
                assert 'Ask Assistant' not in page.locator('body').aria_snapshot()
                page.screenshot(path=str(OUT / '03-after-refresh.png'))
                # Exercise the actual file_selector / XFile browser download.
                page.get_by_role('button', name=TITLE, exact=True).click(button='right', force=True)
                page.get_by_role('button', name='Export This Branch…', exact=True).click(force=True)
                expect(page.get_by_text('Markdown', exact=True)).to_be_visible()
                expect(page.get_by_text('PNG', exact=True)).to_have_count(0)
                expect(page.get_by_text('PDF', exact=True)).to_have_count(0)
                with page.expect_download() as download:
                    page.get_by_role('button', name='Export…', exact=True).click(force=True)
                result = download.value
                assert result.suggested_filename.endswith('.md')
                assert TITLE in Path(result.path()).read_text()
                assert not errors, errors
                (OUT / 'browser-result.json').write_text(json.dumps({
                    'passed': True, 'browser': browser.version,
                    'checks': ['launch', 'create/import PDF', 'render PDF', 'add/rename node',
                               'refresh/reopen', 'persisted PDF and node', 'Markdown download',
                               'no PNG/PDF encoder options', 'no browser errors'],
                    'errors': errors,
                }, indent=2) + '\n')
                print('PASS: create → PDF import → edit → refresh → reopen → download')
            finally:
                browser.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == '__main__':
    main()
