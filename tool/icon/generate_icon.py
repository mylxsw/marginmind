#!/usr/bin/env python3
"""Renders the MarginMind app icon.

A page with one highlighted line, branching out into mind-map cards:
"read, excerpt, map". Drawn at 4x and downsampled for clean edges.

Outputs (relative to the repo root):
  apps/marginmind/assets/icon/app_icon.png        1024², full-bleed squircle
  apps/marginmind/assets/icon/app_icon_macos.png  1024², macOS grid
                                                  (824² body, shadow, padding)

Requires Pillow:  python3 -m pip install pillow
Then run:         ./tool/icons.sh
"""

from __future__ import annotations

import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps" / "marginmind" / "assets" / "icon"
S = 4  # supersampling factor
SIZE = 1024


def squircle(size: int, n: float = 5.0, steps: int = 720) -> list[tuple[float, float]]:
    """Superellipse |x|^n + |y|^n = 1, close to Apple's continuous corners."""
    r = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(c) ** (2 / n), c)
        y = r + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    return pts


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        img.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.resize((size, size))


def rounded_rect(draw: ImageDraw.ImageDraw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def artwork(size: int) -> Image.Image:
    """The icon body (squircle with content), size x size, RGBA."""
    k = size / 1024
    body = vertical_gradient(size, (64, 145, 255), (10, 84, 196)).convert("RGBA")

    # Page, drawn upright on its own layer, then rotated.
    page = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(page)
    px0, py0, px1, py1 = 210 * k, 250 * k, 560 * k, 774 * k
    rounded_rect(d, (px0, py0, px1, py1), 22 * k, (255, 255, 255, 255))
    line_y = [330, 382, 434, 486, 538, 590, 642, 694]
    for i, y in enumerate(line_y):
        x_end = 500 if i not in (3, 7) else (520 if i == 3 else 420)
        y = y * k
        if i == 3:
            rounded_rect(d, (246 * k, y - 18 * k, 524 * k, y + 18 * k), 8 * k, (255, 204, 0, 255))
        rounded_rect(d, (250 * k, y - 6 * k, x_end * k, y + 6 * k), 6 * k, (120, 128, 145, 255) if i == 3 else (200, 206, 218, 255))
    shadow = page.split()[3].filter(ImageFilter.GaussianBlur(18 * k))
    shadow_layer = Image.new("RGBA", (size, size), (6, 40, 110, 0))
    shadow_layer.putalpha(shadow.point(lambda a: a * 0.45))
    page = Image.alpha_composite(shadow_layer.transform((size, size), Image.AFFINE, (1, 0, 0, 0, 1, -10 * k)), page)
    page = page.rotate(6, resample=Image.BICUBIC, center=(385 * k, 512 * k))
    body = Image.alpha_composite(body, page)

    # Branch from the highlighted line to three cards.
    d = ImageDraw.Draw(body)
    start = (548 * k, 470 * k)
    cards = [(792, 330), (812, 512), (792, 694)]
    for cx, cy in cards:
        cx, cy = cx * k, cy * k
        mid = (start[0] + cx) / 2
        pts = []
        for i in range(41):
            t = i / 40
            x = (1 - t) ** 3 * start[0] + 3 * (1 - t) ** 2 * t * mid + 3 * (1 - t) * t ** 2 * mid + t ** 3 * (cx - 80 * k)
            y = (1 - t) ** 3 * start[1] + 3 * (1 - t) ** 2 * t * start[1] + 3 * (1 - t) * t ** 2 * cy + t ** 3 * cy
            pts.append((x, y))
        d.line(pts, fill=(255, 255, 255, 235), width=round(14 * k), joint="curve")
    for i, (cx, cy) in enumerate(cards):
        cx, cy = cx * k, cy * k
        rounded_rect(d, (cx - 92 * k, cy - 44 * k, cx + 92 * k, cy + 44 * k), 26 * k, (255, 255, 255, 255))
        dot = [(255, 204, 0), (52, 199, 89), (175, 82, 222)][i]
        d.ellipse((cx - 62 * k, cy - 13 * k, cx - 36 * k, cy + 13 * k), fill=dot + (255,))
        rounded_rect(d, (cx - 22 * k, cy - 7 * k, cx + 62 * k, cy + 7 * k), 7 * k, (200, 206, 218, 255))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(squircle(size), fill=255)
    body.putalpha(mask)
    return body


def full_bleed() -> Image.Image:
    return artwork(SIZE * S).resize((SIZE, SIZE), Image.LANCZOS)


def macos_grid() -> Image.Image:
    """824² body centered on a 1024² canvas with Apple's soft drop shadow."""
    canvas = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
    body = artwork(824 * S)
    off = 100 * S
    alpha = body.split()[3]
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_alpha = Image.new("L", canvas.size, 0)
    shadow_alpha.paste(alpha, (off, off + 12 * S))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(14 * S)).point(lambda a: a * 0.32)
    shadow.putalpha(shadow_alpha)
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(body, (off, off))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    full_bleed().save(OUT / "app_icon.png")
    macos_grid().save(OUT / "app_icon_macos.png")
    print(f"Wrote {OUT / 'app_icon.png'} and {OUT / 'app_icon_macos.png'}")


if __name__ == "__main__":
    main()
