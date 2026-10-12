#!/usr/bin/env python3
"""Generates Sources/HueBar/Icons/PhosphorIcons.swift from the Phosphor icon set.

Phosphor (https://phosphoricons.com, MIT License, (c) Phosphor Icons) ships SVGs on a 256x256 grid.
SwiftUI can't use SVG path data directly, so each path is rewritten as absolute move/line/cubic/quad
commands (arcs become cubic Béziers) that PhosphorIcon parses at runtime.

Usage: Scripts/generate-phosphor-icons.py [path/to/@phosphor-icons/core/package]
Without an argument the package is downloaded from npm.
"""

import io
import math
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

VERSION = "2.1.1"
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources" / "HueBar" / "Icons" / "PhosphorIcons.swift"

# Swift name -> (Phosphor name, weights). Duotone also needs "regular" for its foreground layer.
ICONS = {
    "lightbulb": ("lightbulb", ["regular", "bold", "fill", "duotone"]),
    "lightbulbFilament": ("lightbulb-filament", ["regular", "fill", "duotone"]),
    "plugs": ("plugs", ["regular", "bold", "duotone"]),
    "plugsConnected": ("plugs-connected", ["regular", "duotone"]),
    "power": ("power", ["regular", "bold"]),
    "gearSix": ("gear-six", ["regular", "duotone"]),
    "arrowsClockwise": ("arrows-clockwise", ["regular", "bold"]),
    "caretDown": ("caret-down", ["bold"]),
    "caretLeft": ("caret-left", ["bold"]),
    "sun": ("sun", ["regular", "fill"]),
    "sunDim": ("sun-dim", ["regular", "fill"]),
    "palette": ("palette", ["regular", "fill", "duotone"]),
    "sparkle": ("sparkle", ["regular", "fill"]),
    "eyedropper": ("eyedropper", ["regular"]),
    "warning": ("warning", ["fill", "duotone"]),
    "wifiSlash": ("wifi-slash", ["regular", "duotone"]),
    "magnifyingGlass": ("magnifying-glass", ["regular", "bold"]),
    "checkCircle": ("check-circle", ["fill"]),
    "circle": ("circle", ["regular"]),
    "signOut": ("sign-out", ["regular"]),
    "trash": ("trash", ["regular"]),
    "rocketLaunch": ("rocket-launch", ["regular"]),
    "link": ("link", ["regular", "bold"]),
    # Rooms
    "house": ("house", ["regular", "duotone"]),
    "couch": ("couch", ["regular", "duotone"]),
    "television": ("television", ["regular", "duotone"]),
    "cookingPot": ("cooking-pot", ["regular", "duotone"]),
    "forkKnife": ("fork-knife", ["regular", "duotone"]),
    "bed": ("bed", ["regular", "duotone"]),
    "baby": ("baby", ["regular", "duotone"]),
    "bathtub": ("bathtub", ["regular", "duotone"]),
    "shower": ("shower", ["regular", "duotone"]),
    "desktop": ("desktop", ["regular", "duotone"]),
    "doorOpen": ("door-open", ["regular", "duotone"]),
    "stairs": ("stairs", ["regular", "duotone"]),
    "tree": ("tree", ["regular", "duotone"]),
    "car": ("car", ["regular", "duotone"]),
    "barbell": ("barbell", ["regular", "duotone"]),
    "bookOpen": ("book-open", ["regular", "duotone"]),
    "squaresFour": ("squares-four", ["regular", "duotone"]),
    # Lights
    "lamp": ("lamp", ["regular", "duotone"]),
    "lampPendant": ("lamp-pendant", ["regular", "duotone"]),
    "plug": ("plug", ["regular", "duotone"]),
}

NUMBER = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")
COMMAND = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]")
PARAM_COUNT = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def tokenize(d):
    """Yields (command, [args...]) groups, expanding implicit repeats."""
    i, n = 0, len(d)
    command = None
    while i < n:
        ch = d[i]
        if ch in " ,\t\n\r":
            i += 1
            continue
        if COMMAND.match(ch):
            command = ch
            i += 1
            if command in "Zz":
                yield command, []
                continue
        if command is None:
            raise ValueError(f"path data starts without a command: {d[:20]}")
        count = PARAM_COUNT[command.upper()]
        args = []
        while len(args) < count:
            while i < n and d[i] in " ,\t\n\r":
                i += 1
            # Arc flags are single digits and may be written without separators ("a8,8,0,0,1-8,8").
            if command in "Aa" and len(args) in (3, 4):
                args.append(float(d[i]))
                i += 1
                continue
            match = NUMBER.match(d, i)
            if not match:
                raise ValueError(f"expected a number at {i} in {d[max(0, i - 10):i + 10]!r}")
            args.append(float(match.group()))
            i = match.end()
        yield command, args
        # Subsequent coordinate pairs after a move are implicit line-tos.
        if command == "M":
            command = "L"
        elif command == "m":
            command = "l"


def arc_to_cubics(x1, y1, rx, ry, phi_deg, large_arc, sweep, x2, y2):
    """SVG arc (endpoint parameterization) to cubic Bézier segments, per SVG 1.1 appendix F.6."""
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [("L", (x2, y2))]
    phi = math.radians(phi_deg)
    cos_phi, sin_phi = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_phi * dx + sin_phi * dy
    y1p = -sin_phi * dx + cos_phi * dy
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        scale = math.sqrt(lam)
        rx, ry = rx * scale, ry * scale
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large_arc == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta = angle(1, 0, ux, uy)
    delta = angle(ux, uy, vx, vy)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi

    segments = max(1, math.ceil(abs(delta) / (math.pi / 2) - 1e-9))
    step = delta / segments
    t = 4 / 3 * math.tan(step / 4)

    def point(a):
        return (
            cx + rx * math.cos(a) * cos_phi - ry * math.sin(a) * sin_phi,
            cy + rx * math.cos(a) * sin_phi + ry * math.sin(a) * cos_phi,
        )

    def derivative(a):
        return (
            -rx * math.sin(a) * cos_phi - ry * math.cos(a) * sin_phi,
            -rx * math.sin(a) * sin_phi + ry * math.cos(a) * cos_phi,
        )

    result = []
    for k in range(segments):
        a1, a2 = theta + k * step, theta + (k + 1) * step
        p1, p2 = point(a1), point(a2)
        d1, d2 = derivative(a1), derivative(a2)
        c1 = (p1[0] + t * d1[0], p1[1] + t * d1[1])
        c2 = (p2[0] - t * d2[0], p2[1] - t * d2[1])
        end = (x2, y2) if k == segments - 1 else p2
        result.append(("C", (*c1, *c2, *end)))
    return result


def simplify(d):
    """Returns the path as absolute M/L/C/Q/Z commands."""
    out = []
    cx = cy = sx = sy = 0.0
    last_cubic = last_quad = None  # reflected control points for S/T
    for command, a in tokenize(d):
        rel = command.islower()
        op = command.upper()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        next_cubic = next_quad = None
        if op == "M":
            cx, cy = a[0] + ox, a[1] + oy
            sx, sy = cx, cy
            out.append(("M", (cx, cy)))
        elif op == "L":
            cx, cy = a[0] + ox, a[1] + oy
            out.append(("L", (cx, cy)))
        elif op == "H":
            cx = a[0] + ox
            out.append(("L", (cx, cy)))
        elif op == "V":
            cy = a[0] + oy
            out.append(("L", (cx, cy)))
        elif op in "CS":
            if op == "C":
                x1, y1, x2, y2, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy, a[4] + ox, a[5] + oy
            else:
                x1, y1 = (2 * cx - last_cubic[0], 2 * cy - last_cubic[1]) if last_cubic else (cx, cy)
                x2, y2, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy
            out.append(("C", (x1, y1, x2, y2, x, y)))
            next_cubic = (x2, y2)
            cx, cy = x, y
        elif op in "QT":
            if op == "Q":
                x1, y1, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy
            else:
                x1, y1 = (2 * cx - last_quad[0], 2 * cy - last_quad[1]) if last_quad else (cx, cy)
                x, y = a[0] + ox, a[1] + oy
            out.append(("Q", (x1, y1, x, y)))
            next_quad = (x1, y1)
            cx, cy = x, y
        elif op == "A":
            x, y = a[5] + ox, a[6] + oy
            out.extend(arc_to_cubics(cx, cy, a[0], a[1], a[2], bool(a[3]), bool(a[4]), x, y))
            cx, cy = x, y
        elif op == "Z":
            out.append(("Z", ()))
            cx, cy = sx, sy
        last_cubic, last_quad = next_cubic, next_quad
    return out


def fmt(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def serialize(commands):
    return " ".join(op + " ".join(fmt(v) for v in args) if args else op for op, args in commands)


def layers(svg):
    """Returns [(d, opacity)] for each <path> in an SVG file."""
    result = []
    for tag in re.findall(r"<path\b[^>]*>", svg):
        d = re.search(r'\bd="([^"]*)"', tag).group(1)
        opacity = re.search(r'\bopacity="([^"]*)"', tag)
        result.append((d, float(opacity.group(1)) if opacity else 1.0))
    return result


def load_package(argv):
    if len(argv) > 1:
        return Path(argv[1])
    target = Path(__file__).resolve().parent / ".phosphor-cache"
    cached = target / "package"
    if (cached / "package.json").exists() and f'"version": "{VERSION}"' in (cached / "package.json").read_text():
        return cached
    url = f"https://registry.npmjs.org/@phosphor-icons/core/-/core-{VERSION}.tgz"
    data = urllib.request.urlopen(url).read()
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        archive.extractall(target, filter="data")
    return target / "package"


def svg_path(package, name, weight):
    suffix = "" if weight == "regular" else f"-{weight}"
    return package / "assets" / weight / f"{name}{suffix}.svg"


def main(argv):
    package = load_package(argv)
    lines = [
        "// Generated by Scripts/generate-phosphor-icons.py from @phosphor-icons/core "
        f"{VERSION}. Do not edit.",
        "// Phosphor Icons, MIT License, Copyright (c) 2023 Phosphor Icons. https://phosphoricons.com",
        "",
        "// swift-format-ignore-file",
        "// swiftlint:disable all",
        "extension PhosphorIcon {",
    ]
    for swift_name, (name, weights) in ICONS.items():
        args = []
        needed = list(dict.fromkeys(weights + (["regular"] if "duotone" in weights else [])))
        for weight in ["regular", "bold", "fill", "duotone"]:
            if weight not in needed:
                continue
            svg = svg_path(package, name, weight).read_text()
            paths = layers(svg)
            if weight == "duotone":
                # The duotone foreground is the regular outline; keep only the translucent background.
                background = [d for d, opacity in paths if opacity < 1]
                assert background, f"{name}: duotone without a background layer"
                args.append(f'duotone: "{serialize(simplify(" ".join(background)))}"')
            else:
                assert all(opacity == 1 for _, opacity in paths), f"{name}-{weight}: unexpected opacity"
                args.append(f'{weight}: "{serialize(simplify(" ".join(d for d, _ in paths)))}"')
        lines.append(f"    static let {swift_name} = PhosphorIcon(")
        lines.append(",\n".join(f"        {arg}" for arg in args))
        lines.append("    )")
    lines.append("")
    lines.append("    /// Every generated icon, for tests and previews.")
    lines.append("    static let all: [(name: String, icon: PhosphorIcon)] = [")
    lines.extend(f'        ("{swift_name}", {swift_name}),' for swift_name in ICONS)
    lines.append("    ]")
    lines.append("}")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines) + "\n")
    print(f"Wrote {len(ICONS)} icons to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main(sys.argv)
