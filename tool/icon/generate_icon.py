#!/usr/bin/env python3
"""Package the approved Foliarc masters for each platform (B is the default).

Artwork is kept in assets/icon/masters. This script only resizes it and applies
platform masks/padding; it never redraws the approved designs. Requires Pillow.
Run ./tool/icons.sh after changing a master.
"""
from __future__ import annotations

import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / 'apps' / 'marginmind'
OUT = APP / 'assets' / 'icon'
VARIANTS = {'paper_arc': 'AppIcon', 'leaf_folio': 'AppIconLeaf', 'folded_f': 'AppIconF'}
SIZE = 1024


def squircle(size: int, n: float = 5.0, steps: int = 720) -> list[tuple[float, float]]:
    r = size / 2
    return [(r + r * math.copysign(abs(math.cos(t)) ** (2 / n), math.cos(t)),
             r + r * math.copysign(abs(math.sin(t)) ** (2 / n), math.sin(t)))
            for t in (2 * math.pi * i / steps for i in range(steps))]


def macos_grid(master: Image.Image) -> Image.Image:
    # Same 824px optical footprint as the existing app icon, on a 1024px canvas.
    scale = 2
    body = master.resize((824 * scale, 824 * scale), Image.Resampling.LANCZOS).convert('RGBA')
    alpha = Image.new('L', body.size, 0)
    ImageDraw.Draw(alpha).polygon(squircle(body.width), fill=255)
    body.putalpha(alpha)
    canvas = Image.new('RGBA', (SIZE * scale, SIZE * scale))
    shadow_alpha = Image.new('L', canvas.size)
    shadow_alpha.paste(alpha, (100 * scale, 112 * scale))
    shadow = Image.new('RGBA', canvas.size)
    shadow.putalpha(shadow_alpha.filter(ImageFilter.GaussianBlur(14 * scale)).point(lambda a: round(a * .24)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(body, (100 * scale, 100 * scale))
    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def write_json(path: pathlib.Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + '\n')


def main() -> None:
    ios_template = json.loads((APP / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
    mac_template = json.loads((APP / 'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text())
    for variant, name in VARIANTS.items():
        master = Image.open(OUT / 'masters' / f'{variant}.png').convert('RGB')
        if master.width != master.height or master.width < SIZE:
            raise ValueError(f'{variant}: master must be square and at least 1024px')
        square = master.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        mac = macos_grid(square)
        # Runtime settings previews are small; don't ship the large source masters in Flutter's asset bundle.
        square.resize((192, 192), Image.Resampling.LANCZOS).save(OUT / f'{variant}.png')
        ios_set = APP / 'ios/Runner/Assets.xcassets' / f'{name}.appiconset'
        ios_set.mkdir(exist_ok=True)
        write_json(ios_set / 'Contents.json', ios_template)
        for entry in ios_template['images']:
            size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
            square.resize((size, size), Image.Resampling.LANCZOS).save(ios_set / entry['filename'])
        runtime = APP / 'macos/Runner/Assets.xcassets' / f'Foliarc{variant.title().replace("_", "")}.imageset'
        runtime.mkdir(exist_ok=True)
        mac.save(runtime / 'icon.png')
        write_json(runtime / 'Contents.json', {'images': [{'filename': 'icon.png', 'idiom': 'universal'}],
                                              'info': {'author': 'xcode', 'version': 1}})
        if variant == 'paper_arc':
            square.save(OUT / 'app_icon.png')
            mac.save(OUT / 'app_icon_macos.png')
            for entry in mac_template['images']:
                size = round(float(entry['size'].split('x')[0]) * float(entry['scale'][:-1]))
                mac.resize((size, size), Image.Resampling.LANCZOS).save(
                    APP / 'macos/Runner/Assets.xcassets/AppIcon.appiconset' / entry['filename'])
            mac.save(APP / 'windows/runner/resources/app_icon.ico', sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
            for size in (256, 512):
                square.resize((size, size), Image.Resampling.LANCZOS).save(APP / f'web/icons/Icon-{size}.png')
            square.resize((32, 32), Image.Resampling.LANCZOS).save(APP / 'web/favicon.png')
            for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
                target = APP / f'android/app/src/main/res/mipmap-{density}'
                target.mkdir(exist_ok=True)
                square.resize((size, size), Image.Resampling.LANCZOS).save(target / 'ic_launcher.png')
    print('Packaged Foliarc icons: Paper Arc (default), Leaf & Folio, Folded F')


if __name__ == '__main__':
    main()
