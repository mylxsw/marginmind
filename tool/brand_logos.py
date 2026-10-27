#!/usr/bin/env python3
"""Turns single-path brand SVGs (Simple Icons, CC0, 24×24 view box) into Dart.

Usage: python3 tool/brand_logos.py NAME=FILE.svg ... > OUTPUT.dart

Every command is written with absolute coordinates, so the Dart side needs
no SVG parser: moveTo / lineTo / cubicTo / quadraticBezierTo / arcToPoint.
"""

import re
import sys

_TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def path_data(svg: str) -> str:
    """The `d` attribute of the only path in [svg]."""
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"', svg)
    if len(paths) != 1:
        raise ValueError(f"expected one path, found {len(paths)}")
    return paths[0]


def _tokens(d: str):
    out = []
    for t in _TOKEN.findall(d):
        out.append(t if t.isalpha() else float(t))
    return out


def _num(v: float) -> str:
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    if s in ("-0", ""):
        s = "0"
    return s


def to_dart(d: str) -> list[str]:
    """Dart statements building the path on `p`."""
    tokens = _tokens(_split_flags(d))
    lines = []
    i, cmd = 0, None
    x = y = sx = sy = 0.0
    last_c = last_q = None  # reflected control points for S / T

    def take(n):
        nonlocal i
        vals = tokens[i : i + n]
        if len(vals) != n or any(isinstance(v, str) for v in vals):
            raise ValueError(f"bad arguments for {cmd} at {i}")
        i += n
        return vals

    while i < len(tokens):
        if isinstance(tokens[i], str):
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                lines.append("p.close();")
                x, y = sx, sy
                last_c = last_q = None
                continue
        elif cmd is None:
            raise ValueError("path must start with a command")
        up = cmd.upper()
        rel = cmd != up
        ox, oy = (x, y) if rel else (0.0, 0.0)
        a = take(_ARGS[up])
        c, q = None, None
        if up == "M":
            x, y = ox + a[0], oy + a[1]
            sx, sy = x, y
            lines.append(f"p.moveTo({_num(x)}, {_num(y)});")
            cmd = "l" if rel else "L"  # Further pairs are line segments.
        elif up == "L":
            x, y = ox + a[0], oy + a[1]
            lines.append(f"p.lineTo({_num(x)}, {_num(y)});")
        elif up == "H":
            x = ox + a[0]
            lines.append(f"p.lineTo({_num(x)}, {_num(y)});")
        elif up == "V":
            y = oy + a[0]
            lines.append(f"p.lineTo({_num(x)}, {_num(y)});")
        elif up in "CS":
            if up == "C":
                x1, y1 = ox + a[0], oy + a[1]
                rest = a[2:]
            else:
                x1, y1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
                rest = a
            x2, y2 = ox + rest[0], oy + rest[1]
            x, y = ox + rest[2], oy + rest[3]
            c = (x2, y2)
            lines.append(f"p.cubicTo({_num(x1)}, {_num(y1)}, {_num(x2)}, {_num(y2)}, {_num(x)}, {_num(y)});")
        elif up in "QT":
            if up == "Q":
                x1, y1 = ox + a[0], oy + a[1]
                ex, ey = ox + a[2], oy + a[3]
            else:
                x1, y1 = (2 * x - last_q[0], 2 * y - last_q[1]) if last_q else (x, y)
                ex, ey = ox + a[0], oy + a[1]
            x, y = ex, ey
            q = (x1, y1)
            lines.append(f"p.quadraticBezierTo({_num(x1)}, {_num(y1)}, {_num(x)}, {_num(y)});")
        elif up == "A":
            rx, ry, rot, large, sweep = a[0], a[1], a[2], int(a[3]), int(a[4])
            x, y = ox + a[5], oy + a[6]
            lines.append(
                f"p.arcToPoint(Offset({_num(x)}, {_num(y)}), radius: Radius.elliptical({_num(abs(rx))}, {_num(abs(ry))}), "
                f"rotation: {_num(rot)}, largeArc: {'true' if large else 'false'}, clockwise: {'true' if sweep else 'false'});"
            )
        last_c, last_q = c, q
    return lines


def _split_flags(d: str) -> str:
    """Separates compact arc flags: "a1 1 0 01.5.5" → "a1 1 0 0 1 .5.5"."""
    out, pos = [], 0
    for m in re.finditer(r"[Aa]", d):
        out.append(d[pos : m.end()])
        pos = m.end()
        # Each arc is rx ry rot large sweep x y; repeat while numbers follow.
        while True:
            seg = re.match(
                r"\s*,?\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*,?\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)"
                r"\s*,?\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*,?\s*([01])\s*,?\s*([01])",
                d[pos:],
            )
            if not seg:
                break
            out.append(" " + " ".join(seg.groups()) + " ")
            pos += seg.end()
            tail = re.match(
                r"\s*,?\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*,?\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)",
                d[pos:],
            )
            if not tail:
                raise ValueError("arc without an end point")
            out.append(" ".join(tail.groups()) + " ")
            pos += tail.end()
    out.append(d[pos:])
    return "".join(out)


def generate(entries: list[tuple[str, str]]) -> str:
    parts = [
        "// Generated by tool/brand_logos.py from Simple Icons (CC0-1.0); do not edit.",
        "// Marks are 24×24 and belong to their owners; they only name each service.",
        "",
        "import 'dart:ui';",
        "",
    ]
    for name, svg in entries:
        parts.append(f"Path {name}Mark() {{")
        parts.append("  final p = Path();")
        parts.extend("  " + line for line in to_dart(path_data(svg)))
        parts.append("  return p;")
        parts.append("}")
        parts.append("")
    return "\n".join(parts)


def main(argv: list[str]) -> int:
    entries = []
    for arg in argv:
        name, _, file = arg.partition("=")
        with open(file, encoding="utf-8") as f:
            entries.append((name, f.read()))
    sys.stdout.write(generate(entries))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
