"""Flat-style self-check for design/prototype/layout-density.html (GUL-610).

Renders every device / theme / layout of the "新方案" scheme, fails on any
blur, shadow or gradient (elements and ::before / ::after, including open
menus, sheets and panels), and replays the same interaction script on a
baseline copy of the prototype so the flat restyle cannot change behaviour.

    uv run --with playwright==1.64.1 python docs/evidence/gul-610/prototype_check.py \
        --baseline <old-layout-density.html> --out <dir>
"""

import argparse
import json
import pathlib
import sys

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[3]
PROTOTYPE = ROOT / 'design/prototype/layout-density.html'
DEVICES = {'mac': ['reader', 'split', 'map'], 'ipadL': ['reader', 'split', 'map'], 'ipadP': ['reader', 'split', 'map'], 'phone': ['reader', 'map']}
THEMES = ['light', 'dark']
STATE_SHOTS = {'aa menu', 'more menu', 'style menu', 'selection toolbar', 'note sheet', 'assistant', 'drawer'}

# Every element and pseudo element under #screen that paints a blur, shadow or gradient.
AUDIT_JS = """() => {
  const bad = [];
  const props = ['boxShadow', 'textShadow', 'backdropFilter', 'filter', 'backgroundImage'];
  const isBad = (k, v) => k === 'backgroundImage' ? /gradient/.test(v) : v && v !== 'none';
  for (const el of document.querySelectorAll('#screen, #screen *')) {
    for (const pseudo of [null, '::before', '::after']) {
      const cs = getComputedStyle(el, pseudo);
      if (pseudo && cs.content === 'none') continue;
      for (const k of props) if (isBad(k, cs[k])) bad.push(`${el.className || el.tagName}${pseudo || ''} ${k}: ${cs[k]}`);
    }
  }
  const css = [...document.styleSheets].flatMap(s => [...s.cssRules].map(r => r.cssText)).join('\\n');
  for (const word of ['backdrop-filter', 'box-shadow', 'text-shadow', 'gradient(', 'blur(', 'drop-shadow'])
    if (css.includes(word)) bad.push(`stylesheet contains ${word}`);
  return bad;
}"""

# A compact, theme-independent snapshot of what the prototype is showing.
STATE_JS = """() => {
  const q = s => document.querySelector(s), qa = s => document.querySelectorAll(s);
  return {
    metric: q('#metric')?.textContent,
    panes: [...qa('.pane')].map(p => p.classList.contains('reader') ? 'reader' : 'map'),
    vert: !!q('.ws.vert'),
    heads: qa('.phead').length,
    tools: [...qa('.tb.on')].map(b => (b.dataset.act || '') + ':' + (b.dataset.arg || '')).sort(),
    seg: [...qa('.segc button.on')].map(b => b.textContent),
    menu: q('.menu') ? (q('.menu').classList.contains('stylepop') ? 'style' : q('.menu').textContent.trim().slice(0, 12)) : null,
    ftb: !!q('.ftb'),
    cards: qa('.node.card').length,
    marks: qa('.pdfpage mark').length,
    selected: q('.node.sel')?.dataset.node || null,
    title: q('.pdfpage h1, .pdfpage h2')?.textContent || null,
    outline: !!q('.outline'),
    compact: !!q('.compactmap'),
    assistant: !!q('.panel.on'),
    sheet: !!q('.sheet.on'),
    drawer: q('.side.drawer') ? !q('.side.drawer').classList.contains('closed') : null,
    hidden: !!q('.app.bars-hidden'),
    zoom: q('.zv')?.textContent || null,
    dock: [...qa('.dock .tb')].length,
  };
}"""


def url(path, **params):
    return path.as_uri() + '?' + '&'.join(f'{k}={v}' for k, v in params.items())


def open_page(browser, path, **params):
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, device_scale_factor=1)
    page.goto(url(path, scheme='new', **params))
    page.wait_for_selector('#screen')
    page.wait_for_timeout(150)
    return page


def act(page, selector):
    # Scroll first: a scroll event that lands after the click dismisses the selection toolbar.
    target = page.locator(selector).first
    # On touch devices that scroll also slides the bars away; scroll back to the top to bring them back.
    if target.evaluate("e => !!e.closest('.phead, .dock') && !!document.querySelector('.app.bars-hidden')"):
        page.locator('#rscroll').evaluate('e => { e.scrollTop = 0; }')
        page.wait_for_timeout(350)
    target.scroll_into_view_if_needed()
    page.wait_for_timeout(120)
    target.click()
    page.wait_for_timeout(350)


def scenario(browser, path, device, theme, audit, out=None):
    """Replays one script, returns the state after every step; audits flatness at each step."""
    page = open_page(browser, path, device=device, theme=theme, layout='reader' if device == 'phone' else 'split')
    steps = []

    def snap(name):
        steps.append([name, page.evaluate(STATE_JS)])
        if out and name in STATE_SHOTS:
            page.locator('.device').screenshot(path=out / f"{device}-{theme}-{name.replace(' ', '-')}.png")
        if audit is not None:
            audit.extend(f'{device}/{theme}/{name}: {b}' for b in page.evaluate(AUDIT_JS))

    snap('open')
    if device == 'phone':
        act(page, '#phead [data-act="menu"][data-arg="more"]'); snap('more menu')
        act(page, '.menu [data-act="sheet"]'); snap('note sheet')
        act(page, '.sheet [data-act="sheet"]'); snap('sheet closed')
        act(page, '.dock [data-act="menu"][data-arg="aa"]'); snap('aa menu')
        act(page, '.menu [data-act="sync"]'); snap('sync off')
        act(page, '.menu [data-act="sync"]'); snap('sync on')
        page.mouse.click(5, 5); act(page, '#phead .segc [data-arg="map"]'); snap('map')
        act(page, '.dock [data-act="mapview"]'); snap('outline')
        act(page, '.dock [data-act="mapview"]'); snap('tree')
        act(page, '.dock [data-act="zoom"][data-arg="1"]'); snap('zoom in')
        act(page, '.dock [data-act="menu"][data-arg="style"]'); snap('style menu')
        act(page, '.menu [data-act="density"][data-arg="compact"]'); snap('compact')
        act(page, '#phead [data-act="assistant"]'); snap('assistant')
        act(page, '.panel [data-act="assistant"]'); snap('assistant closed')
        act(page, '#phead [data-act="sidebar"]'); snap('drawer')
        act(page, '.side [data-act="doc"][data-arg="d2"]'); snap('doc 2')
        act(page, '#phead .segc [data-arg="reader"]'); snap('reader')
    else:
        lead = '#rhead'
        act(page, '[data-act="layout"][data-arg="reader"]'); snap('reader only')
        act(page, '[data-act="layout"][data-arg="map"]'); snap('map only')
        act(page, '#mhead [data-act="layout"][data-arg="split"]'); snap('split')
        act(page, f'{lead} [data-act="menu"][data-arg="aa"]'); snap('aa menu')
        act(page, '.menu [data-act="rstyle"][data-arg="paper"]'); snap('paper')
        act(page, f'{lead} [data-act="menu"][data-arg="docs"]'); snap('docs menu')
        act(page, '.menu [data-act="doc"][data-arg="d1"]'); snap('doc 1')
        act(page, f'{lead} [data-act="tool"][data-arg="highlight"]'); snap('highlight tool')
        act(page, '.pdfpage p[data-block="4"]'); snap('highlighted')
        act(page, f'{lead} [data-act="tool"][data-arg="select"]'); snap('select tool')
        act(page, '.pdfpage p[data-block="8"]'); snap('selection toolbar')
        act(page, '.ftb [data-act="excerpt"][data-arg="b"]'); snap('excerpt')
        act(page, f'{lead} [data-act="sync"]'); snap('sync off')
        act(page, f'{lead} [data-act="sync"]'); snap('sync on')
        act(page, '[data-act="menu"][data-arg="style"]'); snap('style menu')
        act(page, '.menu [data-act="density"][data-arg="compact"]'); snap('compact')
        act(page, '.menu [data-act="structure"][data-arg="mind"]'); snap('structure')
        page.keyboard.press('Escape'); page.wait_for_timeout(300); snap('escape')
        act(page, '.mctl [data-act="zoom"][data-arg="1"]'); snap('zoom in')
        act(page, '.mctl [data-act="fit"]'); snap('fit')
        act(page, '.node[data-node="a"]'); snap('select topic')
        act(page, '.segc [data-arg="outline"]'); snap('outline')
        act(page, '.segc [data-arg="tree"]'); snap('tree')
        act(page, '[data-act="assistant"]'); snap('assistant')
        act(page, '.panel [data-act="assistant"]'); snap('assistant closed')
        act(page, '[data-act="sheet"]'); snap('note sheet')
        act(page, '.sheet .btn.pri'); snap('sheet closed')
        page.keyboard.press('Control+1'); page.wait_for_timeout(300); snap('ctrl 1')
        page.keyboard.press('Control+2'); page.wait_for_timeout(300); snap('ctrl 2')
        if device != 'mac':
            act(page, f'{lead} [data-act="sidebar"]'); snap('drawer')
            act(page, '.scrim'); snap('drawer closed')
    if device != 'mac':
        page.locator('#rscroll').evaluate('e => { e.scrollTop = 0; }'); page.wait_for_timeout(100)
        for y in (120, 260, 400):
            page.locator('#rscroll').evaluate(f'e => {{ e.scrollTop = {y}; }}'); page.wait_for_timeout(80)
        page.wait_for_timeout(350); snap('scrolled down')
        page.locator('#rscroll').evaluate('e => { e.scrollTop = 200; }'); page.wait_for_timeout(450); snap('scrolled up')
    page.close()
    return steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--baseline', type=pathlib.Path, help='previous prototype, for the interaction regression')
    ap.add_argument('--out', type=pathlib.Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    report = {'audit': [], 'screens': [], 'regression': {}}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for device, layouts in DEVICES.items():
            for theme in THEMES:
                for layout in layouts:
                    page = open_page(browser, PROTOTYPE, device=device, theme=theme, layout=layout)
                    report['audit'] += [f'{device}/{theme}/{layout}: {b}' for b in page.evaluate(AUDIT_JS)]
                    name = f'{device}-{theme}-{layout}.png'
                    page.locator('.device').screenshot(path=a.out / name)
                    report['screens'].append(name)
                    page.close()
                new = scenario(browser, PROTOTYPE, device, theme, report['audit'], a.out)
                if a.baseline:
                    old = scenario(browser, a.baseline.resolve(), device, theme, None)
                    diffs = [f'{n}: {k} {o[k]!r} -> {s[k]!r}' for (n, s), (_, o) in zip(new, old) for k in s if s[k] != o[k]]
                    report['regression'][f'{device}/{theme}'] = {'steps': len(new), 'diffs': diffs}
        browser.close()
    (a.out / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    diffs = sum(len(r['diffs']) for r in report['regression'].values())
    steps = sum(r['steps'] for r in report['regression'].values())
    print(f"screens: {len(report['screens'])}  flat violations: {len(report['audit'])}  regression: {steps} steps, {diffs} diffs")
    for line in report['audit'][:20]: print('  audit', line)
    for k, r in report['regression'].items():
        for d in r['diffs'][:10]: print('  diff', k, d)
    sys.exit(1 if report['audit'] or diffs else 0)


if __name__ == '__main__':
    main()
