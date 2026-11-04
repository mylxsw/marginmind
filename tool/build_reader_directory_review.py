#!/usr/bin/env python3
"""Compare the reader navigation region using unchanged system originals."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'docs/evidence/mobile-surface-hierarchy-2026-11-04'


def build(names, reference, output_name):
    verified = json.loads((OUTPUT / 'screenshots.json').read_text())
    font = ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc', 26)
    width, height, gap, caption = 540, round(540 * 1500 / 1206), 24, 52
    board = Image.new('RGB', (width * 2 + gap * 3, (height + caption) * 3 + gap * 4), '#f3f4f5')
    draw = ImageDraw.Draw(board)
    proof = {}
    for row, (name, title) in enumerate(names):
        for col, folder in enumerate([reference, 'iphone']):
            path = OUTPUT / folder / name
            sha = hashlib.sha256(path.read_bytes()).hexdigest()
            if col == 1 and sha != verified['screenshots'][name]['sha256']:
                raise RuntimeError(f'Screenshot changed after validation: {name}')
            proof[f'{folder}/{name}'] = sha
            x, y = gap + col * (width + gap), gap + row * (height + caption + gap)
            draw.text((x, y + 8), title + (' · 修改前' if col == 0 else ' · 修改后'), font=font, fill='#202124')
            with Image.open(path) as image:
                region = image.convert('RGB').crop((0, 0, 1206, 1500))
                board.paste(region.resize((width, height), Image.Resampling.LANCZOS), (x, y + caption))
    board.save(OUTPUT / (output_name + '.jpg'), quality=95)
    (OUTPUT / (output_name + '.json')).write_text(json.dumps({
        'region': [0, 0, 1206, 1500],
        'before_build': json.loads((OUTPUT / reference / 'build-source.json').read_text()),
        'after_build': json.loads((OUTPUT / 'iphone/build-source.json').read_text()),
        'original_sha256': proof,
    }, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--header', action='store_true')
    parser.add_argument('--plain', action='store_true')
    args = parser.parse_args()
    if args.plain:
        build([
            ('dark-08-native-outline.png', '原生目录'),
            ('dark-04-reader-management-outline.png', '管理目录'),
            ('light-04-reader-management-outline.png', '浅色目录'),
        ], 'reference-plain-outline', 'directory-plain-before-after')
    elif args.header:
        for theme in ['dark', 'light']:
            build([
                (f'{theme}-08-native-outline.png', '原生目录'),
                (f'{theme}-04-reader-management-outline.png', '管理目录'),
                (f'{theme}-04b-reader-management-bookmarks.png', '书签管理'),
            ], 'reference-directory-header', f'directory-header-before-after-{theme}')
    else:
        build([
            ('dark-08-native-outline.png', '原生目录'),
            ('dark-04-reader-management-outline.png', '管理目录'),
            ('light-04-reader-management-outline.png', '浅色目录'),
        ], 'reference-directory', 'directory-typography-before-after')


if __name__ == '__main__':
    main()
