#!/usr/bin/env python3
"""Package real simulator captures as a local visual review, without altering originals."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont


SCREENS = [
    ('01-library', '资料库', '补足搜索分割线与“继续学习”之间的留白；标题允许两行，待复习数量移出标题行。'),
    ('02-resources-add', '资料目录 · 添加', '目录用明确文字返回当前内容；添加菜单直接显示操作，不再重复显示标题、分割线或关闭按钮。'),
    ('03-assistant', 'AI 助手', '统一取消手机关闭叉号；推荐操作与输入区对齐，输入区底部收成一排，提及和联网收在加号菜单中。'),
    ('04-map-selection', '脑图 · 选中节点', '专用助手图标；统一实色工具栏；实际定位操作将当前节点和直接子节点一起纳入视野，不额外调整截图缩放。'),
    ('05-assistant-actions', 'AI 快捷操作', '无重复外框、关闭或侧边栏按钮；输入框在半屏、展开、键盘弹出时始终位于面板底部。'),
    ('06-outline-more', '脑图列表 · 更多', '根级菜单直接显示操作；进入子菜单才保留具体标题和返回按钮，字号、图标、行高和对齐一致。'),
    ('07-outline', '脑图列表', '正文优先，来源下移去重；列表视口同时避开顶部导航和底部工具栏；两种底部工具栏使用相同实色材质。'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-dir', type=Path, required=True)
    parser.add_argument('--allow-native-drift', action='store_true',
                        help='Package Flutter-only evidence while explicitly recording concurrent native changes')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / 'docs/evidence/phone-visual-polish-2026-11-03'
    captures = output / 'final-iphone'
    if 'All tests passed!' not in (captures / 'run.log').read_text():
        raise RuntimeError('The current simulator capture run has not passed')
    capture_started = (captures / 'build-source.json').stat().st_mtime
    for path in captures.glob('*.png'):
        if path.stat().st_mtime < capture_started:
            raise RuntimeError(f'Screenshot predates the current build: {path.name}')
    reference = output / 'reference'
    reference.mkdir(exist_ok=True)
    manifest = {}
    for index, (name, title, _) in enumerate(SCREENS, 1):
        original = args.reference_dir / f'{index}-Photo-{index}.jpg'
        shutil.copyfile(original, reference / f'{index:02}.jpg')
        for theme in ['dark', 'light']:
            path = captures / f'{theme}-{name}.png'
            with Image.open(path) as image:
                size = image.size
            manifest[str(path.relative_to(output))] = {
                'title': title, 'size': size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            }
    for path in sorted(captures.glob('*.png')):
        key = str(path.relative_to(output))
        if key not in manifest:
            with Image.open(path) as image:
                size = image.size
            manifest[key] = {'size': size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    source = hashlib.sha256()
    for directory in [root / 'apps/marginmind/lib', root / 'packages']:
        for file in sorted(directory.rglob('*.dart')):
            if 'lib' in file.parts:
                source.update(str(file.relative_to(root)).encode())
                source.update(file.read_bytes())
    build = json.loads((captures / 'build-source.json').read_text())
    if source.hexdigest() != build['dart_source_sha256']:
        raise RuntimeError('Current business source differs from the captured build')
    native = hashlib.sha256()
    for file in sorted((root / 'apps/marginmind/ios/Runner').rglob('*.swift')):
        native.update(str(file.relative_to(root)).encode())
        native.update(file.read_bytes())
    native_matches = native.hexdigest() == build['native_swift_sha256']
    if not native_matches and not args.allow_native_drift:
        raise RuntimeError('Current native source differs from the captured build')
    (output / 'screenshots.json').write_text(json.dumps({
        'verified_dart_source_sha256': source.hexdigest(),
        'captured_native_swift_sha256': build['native_swift_sha256'],
        'current_native_swift_sha256': native.hexdigest(),
        'native_source_matches': native_matches, 'screenshots': manifest,
    }, ensure_ascii=False, indent=2))

    cards = []
    for index, (name, title, note) in enumerate(SCREENS, 1):
        cards.append(f'''<article id="screen-{index}"><h2><span>{index:02}</span> {html.escape(title)}</h2>
<div class="images"><figure class="before"><figcaption>你提供的原图</figcaption><a href="reference/{index:02}.jpg" target="_blank"><img src="reference/{index:02}.jpg" alt="{title}原图"></a></figure>
<figure><figcaption class="after-label">修改后 · 深色</figcaption><a class="after-link" href="final-iphone/dark-{name}.png" target="_blank"><img class="after-image" data-name="{name}" src="final-iphone/dark-{name}.png" alt="{title}修改后截图"></a></figure></div>
<p>{html.escape(note)}</p></article>''')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>移动端 UI 修复 · 七页截图</title><style>
*{box-sizing:border-box}body{margin:0;background:#f3f4f5;color:#202124;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}main{max-width:1520px;margin:auto;padding:40px 32px}h1{font-size:32px;letter-spacing:-1px;margin:0 0 12px}header p{color:#60646c;max-width:860px;line-height:1.8}nav{display:flex;align-items:center;gap:10px;margin:24px 0 32px;flex-wrap:wrap}button{font:inherit;border:1px solid #d4d7dd;background:white;padding:10px 18px;border-radius:10px;cursor:pointer}button[aria-pressed=true]{background:#202124;color:white;border-color:#202124}label{margin-left:12px;cursor:pointer}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}.compare .grid{grid-template-columns:repeat(auto-fit,minmax(min(100%,520px),1fr))}article{background:white;border:1px solid #e2e4e8;border-radius:16px;padding:20px}h2{font-size:18px;margin:0 0 16px}h2 span{color:#747982;margin-right:8px;font-size:14px}.images{display:grid;grid-template-columns:1fr;gap:16px}.compare .images{grid-template-columns:1fr 1fr}.before{display:none}.compare .before{display:block}figure{margin:0;min-width:0}figcaption{font-size:12px;color:#737982;margin-bottom:8px}img{display:block;width:100%;border:1px solid #e4e6ea;border-radius:10px}article p{line-height:1.7;color:#60646c;font-size:13px;margin-bottom:0}footer{margin-top:28px;color:#737982;line-height:1.8;font-size:13px}a{color:#176bcc}@media(max-width:600px){main{padding:24px 14px}.grid{gap:16px}article{padding:14px}h1{font-size:26px}}
</style><main><header><h1>移动端 UI 修复</h1><p>对应你提供的七张截图。以下均为修改后的真实应用在 iPhone 17 Pro / iOS 26.5 模拟器中的系统截图，使用本地示例内容复现页面状态。点击图片可查看原图。</p></header>
<nav><button data-theme="dark" aria-pressed="true">深色</button><button data-theme="light" aria-pressed="false">浅色</button><label><input type="checkbox" id="compare"> 显示修改前对照</label></nav>
<section class="grid">''' + '\n'.join(cards) + '''</section><footer>截图保留系统原图；示例文字、模型预览和脑图位置与原设备数据不同。本轮未安装到实体手机，未发送 AI 请求。<br>另附 <a href="pages-two-columns-3.jpg" target="_blank">半屏及键盘状态拼图</a>、<a href="final-iphone/dark-05a-assistant-actions-expanded.png" target="_blank">快捷面板展开状态</a>、<a href="final-iphone/dark-07a-outline-bottom.png" target="_blank">列表末尾</a> 和 <a href="README.md">验证记录</a>。</footer></main>
<script>for(const button of document.querySelectorAll('[data-theme]'))button.onclick=()=>{const theme=button.dataset.theme;for(const b of document.querySelectorAll('[data-theme]'))b.setAttribute('aria-pressed',String(b===button));for(const img of document.querySelectorAll('.after-image')){img.src=`final-iphone/${theme}-${img.dataset.name}.png`;img.closest('a').href=img.src;}for(const label of document.querySelectorAll('.after-label'))label.textContent=`修改后 · ${theme==='dark'?'深色':'浅色'}`;};document.querySelector('#compare').onchange=e=>document.body.classList.toggle('compare',e.target.checked);</script></html>'''
    (output / 'review.html').write_text(page)

    # Presentation sheets only: source screenshots above remain byte-for-byte intact.
    font_path = '/System/Library/Fonts/STHeiti Medium.ttc'
    font = ImageFont.truetype(font_path, 21)
    small = ImageFont.truetype(font_path, 14)
    for theme in ['dark', 'light']:
        sheet = Image.new('RGB', (1280, 1540), '#f3f4f5')
        draw = ImageDraw.Draw(sheet)
        draw.text((24, 20), f'移动端 UI 修复 · {"深色" if theme == "dark" else "浅色"} · iPhone 模拟器实际截图', font=font, fill='#202124')
        for i, (name, title, _) in enumerate(SCREENS):
            x = 24 + (i % 4) * 314
            y = 68 + (i // 4) * 730
            draw.text((x, y), f'{i + 1:02}  {title}', font=small, fill='#555b64')
            with Image.open(captures / f'{theme}-{name}.png') as original:
                thumb = original.convert('RGB')
                thumb.thumbnail((290, 680), Image.Resampling.LANCZOS)
                sheet.paste(thumb, (x, y + 28))
        draw.text((966, 902), '实色面板 / 统一标题栏', font=small, fill='#555b64')
        draw.text((966, 930), '统一菜单 / 清晰边界', font=small, fill='#555b64')
        draw.text((966, 958), '正文优先 / 紧凑工具栏', font=small, fill='#555b64')
        sheet.save(output / f'overview-{theme}.jpg', quality=93)
    sheet = Image.new('RGB', (1280, 810), '#f3f4f5')
    draw = ImageDraw.Draw(sheet)
    draw.text((24, 20), '本轮修正 · 标题留白 / 输入框宽度 / 专用图标 / 去掉冗余入口', font=font, fill='#202124')
    for col, index in enumerate([0, 2, 3, 4]):
        name, title, _ = SCREENS[index]
        x = 24 + col * 314
        draw.text((x, 68), title, font=small, fill='#555b64')
        with Image.open(captures / f'dark-{name}.png') as original:
            thumb = original.convert('RGB')
            thumb.thumbnail((290, 680), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (x, 96))
    sheet.save(output / 'followup-focus.jpg', quality=93)
    groups = [
        [(f'dark-{name}', f'{i + 1:02} {title}') for i, (name, title, _) in enumerate(SCREENS[:6])],
        [('dark-07-outline', '07 脑图列表 · 深色'), ('light-07-outline', '07 脑图列表 · 浅色'),
         ('dark-05a-assistant-actions-expanded', '快捷面板展开 · 深色'), ('light-05a-assistant-actions-expanded', '快捷面板展开 · 浅色'),
         ('dark-07a-outline-bottom', '列表底部 · 深色'), ('light-07a-outline-bottom', '列表底部 · 浅色')],
        [('dark-03a-assistant-medium', '完整助手半屏 · 深色'), ('light-03a-assistant-medium', '完整助手半屏 · 浅色'),
         ('dark-03b-assistant-keyboard', '完整助手与键盘 · 深色'), ('light-03b-assistant-keyboard', '完整助手与键盘 · 浅色'),
         ('dark-05b-assistant-actions-keyboard', '快捷助手与键盘 · 深色'), ('light-05b-assistant-actions-keyboard', '快捷助手与键盘 · 浅色')],
        [(f'light-{name}', f'{i + 1:02} {title} · 浅色') for i, (name, title, _) in enumerate(SCREENS[:6])],
        [('dark-02a-resources', '目录 · 返回脑图'), ('dark-02b-resources-reading', '目录 · 返回阅读'),
         ('dark-02-resources-add', '添加操作 · 深色'), ('light-02-resources-add', '添加操作 · 浅色'),
         ('dark-06-outline-more', '更多操作 · 无重复标题'), ('dark-06a-map-submenu', '子菜单 · 保留返回与标题')],
    ]
    collage_font = ImageFont.truetype(font_path, 28)
    width = 540
    for page, group in enumerate(groups, 1):
        with Image.open(captures / f'{group[0][0]}.png') as image:
            height = round(width * image.height / image.width)
        gap, label = 24, 52
        row = height + label
        sheet = Image.new('RGB', (width * 2 + gap * 3, row * 3 + gap * 4), '#f3f4f5')
        draw = ImageDraw.Draw(sheet)
        for slot, (name, title) in enumerate(group):
            x, y = gap + (slot % 2) * (width + gap), gap + (slot // 2) * (row + gap)
            draw.text((x, y + 8), title, font=collage_font, fill='#202124')
            with Image.open(captures / f'{name}.png') as image:
                sheet.paste(image.convert('RGB').resize((width, height), Image.Resampling.LANCZOS), (x, y + label))
        sheet.save(output / f'pages-two-columns-{page}.jpg', quality=94)
    # Exact supplied reference and new capture in the same visual QA artifact.
    for index, (name, title, _) in enumerate(SCREENS, 1):
        sheet = Image.new('RGB', (644, 780), '#f3f4f5')
        draw = ImageDraw.Draw(sheet)
        draw.text((16, 12), f'{index:02}  {title}', font=font, fill='#202124')
        for x, label, path in [(16, '修改前 · 用户截图', reference / f'{index:02}.jpg'),
                               (330, '修改后 · 模拟器截图', captures / f'dark-{name}.png')]:
            draw.text((x, 52), label, font=small, fill='#555b64')
            with Image.open(path) as original:
                thumb = original.convert('RGB')
                thumb.thumbnail((298, 680), Image.Resampling.LANCZOS)
                sheet.paste(thumb, (x, 82))
        sheet.save(output / f'compare-{index:02}.jpg', quality=93)
    if not native_matches:
        page = (output / 'review.html').read_text()
        page = page.replace('<footer>', '<footer>本轮 Flutter 页面代码与截图构建一致；原生弹窗代码在采集中另有更新，截图保留验收构建的原生版本，具体指纹见 screenshots.json。<br>')
        (output / 'review.html').write_text(page)
    print(f'Packaged {len(manifest)} screenshots; Flutter source matches captured build; native matches: {native_matches}.')


if __name__ == '__main__':
    main()
