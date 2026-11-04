#!/usr/bin/env python3
"""Package verified iOS/Flutter surface captures without changing the originals."""
import hashlib
import html
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs/evidence/mobile-surface-hierarchy-2026-11-04'
CAPTURES = OUTPUT / 'iphone'


def digest(directories, suffix, require_lib=False):
    result = hashlib.sha256()
    for directory in directories:
        for path in sorted(directory.rglob(suffix)):
            if not require_lib or 'lib' in path.parts:
                result.update(str(path.relative_to(ROOT)).encode())
                result.update(path.read_bytes())
    return result.hexdigest()


def main():
    if 'All tests passed!' not in (CAPTURES / 'run.log').read_text():
        raise RuntimeError('Flutter acceptance has not passed')
    build = json.loads((CAPTURES / 'build-source.json').read_text())
    dart = digest([ROOT / 'apps/marginmind/lib', ROOT / 'packages'], '*.dart', True)
    swift = digest([ROOT / 'apps/marginmind/ios/Runner'], '*.swift')
    if dart != build['dart_source_sha256'] or swift != build['native_swift_sha256']:
        raise RuntimeError('Current application source differs from the captured build')
    for theme in ['dark', 'light']:
        action = 'ReaderHierarchy' + theme.title()
        summary = json.loads((CAPTURES / f'native-{action}-summary.json').read_text())
        if summary['result'] != 'Passed':
            raise RuntimeError(f'Native acceptance failed: {action}')
        native = CAPTURES / f'native-{action}'
        exports = json.loads((native / 'manifest.json').read_text())
        found = set()
        for test in exports:
            for attachment in test['attachments']:
                name = attachment['suggestedHumanReadableName']
                for number, section in [(1, 'outline'), (2, 'bookmarks'), (3, 'annotations')]:
                    if name.startswith(f'{theme}-{number:02}-native-{section}_'):
                        shutil.copyfile(native / attachment['exportedFileName'], CAPTURES / f'{theme}-08-native-{section}.png')
                        found.add(section)
        if found != {'outline', 'bookmarks', 'annotations'}:
            raise RuntimeError(f'Incomplete native screenshots: {theme}')
    started = (CAPTURES / 'build-source.json').stat().st_mtime
    manifest = {}
    for path in sorted(CAPTURES.glob('*.png')):
        if path.stat().st_mtime < started:
            raise RuntimeError(f'Stale screenshot: {path.name}')
        with Image.open(path) as original:
            size = original.size
        manifest[path.name] = {'size': size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    if len(manifest) != 32:
        raise RuntimeError(f'Expected 32 screenshots, found {len(manifest)}')
    (OUTPUT / 'screenshots.json').write_text(json.dumps({
        'verified_dart_source_sha256': dart, 'verified_native_swift_sha256': swift,
        'screenshots': manifest,
    }, ensure_ascii=False, indent=2))
    font = ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc', 28)
    primary = [
        ('08-native-outline', '阅读目录 · 标签页'), ('04-reader-management-outline', '目录管理 · 单层面板'),
        ('05-assistant-expanded', 'AI 助手 · 默认展开'), ('06-quick-actions', 'AI 快捷操作 · 较高面板'),
        ('01-library-drawer', '资料库导航 · Drawer'), ('02-study-drawer', '学习集导航 · 单行标题'),
    ]
    groups = [[(f'{theme}-{name}', title) for name, title in primary] for theme in ['dark', 'light']]
    groups += [
        [('dark-08-native-outline', '阅读目录'), ('dark-04-reader-management-outline', '目录管理'),
         ('dark-08-native-bookmarks', '书签浏览'), ('dark-04b-reader-management-bookmarks', '书签管理'),
         ('dark-08-native-annotations', '标注浏览'), ('dark-04c-reader-management-annotations', '标注管理')],
        [('dark-05b-assistant-keyboard', 'AI 键盘 · 深色'), ('light-05b-assistant-keyboard', 'AI 键盘 · 浅色'),
         ('dark-03-add-menu', '短菜单 · 按内容'), ('light-03-add-menu', '短菜单 · 浅色'),
         ('dark-07-settings', '设置 · 默认展开'), ('light-07-settings', '设置 · 浅色')],
        [(f'{theme}-{name}', title) for name, title in [('09-map-style', '脑图样式 · 单层面板'), ('10-reading-settings', '阅读设置 · 按内容'), ('00-library', '资料库 · 间距与角标')] for theme in ['dark', 'light']],
    ]
    groups.append([(name.replace('dark-', 'light-', 1), title) for name, title in groups[2]])
    width, gap, label = 540, 24, 52
    with Image.open(CAPTURES / 'dark-01-library-drawer.png') as original:
        height = round(width * original.height / original.width)
    for page, group in enumerate(groups, 1):
        sheet = Image.new('RGB', (width * 2 + gap * 3, (height + label) * 3 + gap * 4), '#f3f4f5')
        draw = ImageDraw.Draw(sheet)
        for index, (name, title) in enumerate(group):
            x = gap + index % 2 * (width + gap)
            y = gap + index // 2 * (height + label + gap)
            draw.text((x, y + 8), title, font=font, fill='#202124')
            with Image.open(CAPTURES / f'{name}.png') as original:
                sheet.paste(original.convert('RGB').resize((width, height), Image.Resampling.LANCZOS), (x, y + label))
        sheet.save(OUTPUT / f'pages-two-columns-{page}.jpg', quality=94)
    descriptions = [
        ('08-native-outline', '阅读目录', '把手后直接显示文字标签，管理与标签同行；无文档标题栏、关闭按钮及内层卡片。'),
        ('04-reader-management-outline', '目录管理', '无独立文档标题栏；目录、书签、标注直接铺在面板底板，添加和排序操作随内容显示。'),
        ('05-assistant-expanded', 'AI 助手', '完整对话默认展开；推荐操作使用平面列表，输入和发送避让键盘。'),
        ('06-quick-actions', 'AI 快捷操作', '临时操作使用 70% 初始高度，输入区保持贴底。'),
        ('01-library-drawer', '资料库导航', '侧滑 Drawer 保留外部可点击区域，点选、遮罩、滑动和返回均可退出。'),
        ('02-study-drawer', '学习集导航', '侧滑 Drawer；文档单行省略，去掉右上角返回文字，保留资料库入口。'),
    ]
    cards = ''.join(f'<article><h2>{html.escape(title)}</h2><a href="iphone/dark-{name}.png" class="link"><img data-name="{name}" src="iphone/dark-{name}.png" alt="{html.escape(title)}"></a><p>{html.escape(note)}</p></article>' for name, title, note in descriptions)
    (OUTPUT / 'review.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>移动端面板与导航复核</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3f4f5;color:#202124;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}main{max-width:1300px;margin:auto;padding:32px 20px}h1{font-size:28px}nav{display:flex;gap:12px;margin:24px 0}button{font:inherit;padding:10px 20px;border-radius:10px;background:white;border:1px solid #d4d7dd;cursor:pointer}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{background:white;border-radius:14px;padding:18px}h2{font-size:18px}img{width:100%;display:block}p,footer{line-height:1.7;color:#60646c}a{color:#176bcc}@media(max-width:600px){.grid{grid-template-columns:1fr}}
</style><main><h1>移动端面板与导航复核</h1><p>真实 iPhone 模拟器运行截图，使用本地示例资料。原生导航与 Flutter 页面均经过运行验收。</p><nav><button data-theme="dark">深色</button><button data-theme="light">浅色</button></nav><section class="grid">''' + cards + '''</section><footer><a href="directory-plain-before-after.jpg">本轮简化章节目录</a>。<a href="directory-header-before-after-dark.jpg">上一轮标题清理</a>（<a href="directory-header-before-after-light.jpg">浅色</a>）。另附 <a href="pages-two-columns-3.jpg">目录 / 书签 / 标注逐页复核</a>（<a href="pages-two-columns-6.jpg">浅色</a>）、<a href="pages-two-columns-4.jpg">键盘与初始高度</a>、<a href="pages-two-columns-5.jpg">相关面板与资料库</a>、<a href="README.md">验证记录</a>。</footer></main><script>for(const b of document.querySelectorAll('button'))b.onclick=()=>{for(const img of document.querySelectorAll('img')){img.src=`iphone/${b.dataset.theme}-${img.dataset.name}.png`;img.closest('a').href=img.src;}}</script></html>''')
    print(f'Packaged {len(manifest)} real screenshots; Dart and Swift sources both match the capture build.')


if __name__ == '__main__':
    main()
