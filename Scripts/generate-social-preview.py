#!/usr/bin/env python3
"""Generates assets/social-preview.svg and .png, the GitHub social preview (1280x640).

Draws the app icon, wordmark and a mock of the HueBar menu with Phosphor icons. Rendering the PNG
needs rsvg-convert (`brew install librsvg`) and the Inter and JetBrains Mono fonts.
Upload the PNG under Settings -> General -> Social preview; GitHub has no API for it.
"""

import html
import importlib.util
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("icons", Path(__file__).with_name("generate-phosphor-icons.py"))
_icons = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_icons)
PH = _icons.load_package([]) / "assets"
LOGO = (ROOT / "assets" / "logo.svg").read_text()
OUT = ROOT / "assets" / "social-preview.svg"
W, H = 1280, 640

def icon(name, weight, x, y, size, fill, opacity=1.0):
    suffix = "" if weight == "regular" else f"-{weight}"
    svg = (PH / weight / f"{name}{suffix}.svg").read_text()
    paths = "".join(re.findall(r"<path\b[^>]*/>", svg))
    s = size / 256
    return f'<g transform="translate({x:.1f} {y:.1f}) scale({s:.4f})" fill="{fill}" opacity="{opacity}">{paths}</g>'

def logo(x, y, size):
    inner = re.search(r"<svg[^>]*>(.*)</svg>", LOGO, re.S).group(1)
    inner = re.sub(r"<title>.*?</title>", "", inner)
    for ident in ["bg", "hue", "spot", "rim", "glow", "grain", "shadow", "tile"]:
        inner = inner.replace(f'id="{ident}"', f'id="logo-{ident}"').replace(f"url(#{ident})", f"url(#logo-{ident})")
    return f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="0 0 1024 1024">{inner}</svg>'

def text(x, y, s, size, weight=400, fill="#FFFFFF", family="Inter", anchor="start", spacing=0, extra=""):
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}" letter-spacing="{spacing}" {extra}>{html.escape(s)}</text>')

def toggle(x, y, on, grad):
    knob_x = x + 38 - 11 if on else x + 11
    track = f'url(#{grad})' if on else "#FFFFFF"
    op = 1 if on else 0.16
    return (f'<rect x="{x}" y="{y}" width="38" height="22" rx="11" fill="{track}" fill-opacity="{op}"/>'
            f'<circle cx="{knob_x}" cy="{y + 11}" r="8.5" fill="#FFFFFF" filter="url(#knob)"/>')

def level(x, y, w, pct, grad, label):
    h = 26
    filled = w * pct / 100
    out = [f'<clipPath id="clip-{grad}-{y}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="13"/></clipPath>',
           f'<g clip-path="url(#clip-{grad}-{y})">',
           f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#FFFFFF" fill-opacity="0.08"/>']
    if pct:
        out.append(f'<rect x="{x}" y="{y}" width="{filled:.1f}" height="{h}" fill="url(#{grad})"/>')
    out.append("</g>")
    on_fill = "#000000" if pct else "#FFFFFF"
    on_op = 0.72 if pct else 0.45
    out.append(icon("sun-dim", "fill", x + 8, y + 6, 14, on_fill, on_op))
    label_fill = "#000000" if pct > 85 else "#FFFFFF"
    label_op = 0.72 if pct > 85 else 0.55
    out.append(text(x + w - 10, y + 17.5, label, 11.5, 600, label_fill, anchor="end", extra=f'fill-opacity="{label_op}"'))
    return "".join(out)

def card(x, y, w, name, subtitle, room_icon, grad, on, pct):
    h = 98
    tint = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="url(#{grad}-diag)" fill-opacity="0.16"/>'
            f'<rect x="{x + 0.5}" y="{y + 0.5}" width="{w - 1}" height="{h - 1}" rx="13.5" fill="none" stroke="url(#{grad}-diag)" stroke-opacity="0.5"/>'
            if on else
            f'<rect x="{x + 0.5}" y="{y + 0.5}" width="{w - 1}" height="{h - 1}" rx="13.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.06"/>')
    tile_fill = f'url(#{grad}-diag)' if on else "#FFFFFF"
    tile_op = 1 if on else 0.08
    icon_fill, icon_op = ("#000000", 0.72) if on else ("#FFFFFF", 0.55)
    return "".join([
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" fill="#FFFFFF" fill-opacity="0.05"/>', tint,
        f'<rect x="{x + 12}" y="{y + 12}" width="34" height="34" rx="10" fill="{tile_fill}" fill-opacity="{tile_op}"/>',
        icon(room_icon, "duotone", x + 19, y + 19, 20, icon_fill, icon_op),
        text(x + 56, y + 27, name, 13.5, 600),
        text(x + 56, y + 43, subtitle, 11.5, 400, "#FFFFFF", extra='fill-opacity="0.55"'),
                toggle(x + w - 50, y + 18, on, grad),
        level(x + 12, y + 60, w - 24, pct, grad, f"{pct}%" if pct else "Off"),
    ])

def gradient(ident, stops, x2=1, y2=0):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{ident}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'

warm = [(0, "#FFD66B"), (1, "#FF8A5B")]
cool = [(0, "#5EE7F5"), (1, "#6C7CFF")]
hue = [(0, "#FFD66B"), (0.4, "#FF7A59"), (0.72, "#E24FD3"), (1, "#5C7CFF")]

defs = "".join([
    '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#211A4E"/><stop offset="0.6" stop-color="#110E26"/><stop offset="1" stop-color="#07060F"/></linearGradient>',
    '<radialGradient id="glow-amber" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FF9F5A" stop-opacity="0.42"/><stop offset="1" stop-color="#FF9F5A" stop-opacity="0"/></radialGradient>',
    '<radialGradient id="glow-pink" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E24FD3" stop-opacity="0.30"/><stop offset="1" stop-color="#E24FD3" stop-opacity="0"/></radialGradient>',
    '<radialGradient id="glow-blue" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#5C7CFF" stop-opacity="0.32"/><stop offset="1" stop-color="#5C7CFF" stop-opacity="0"/></radialGradient>',
    gradient("title", hue, 1, 0.3),
    gradient("warm", warm), gradient("warm-diag", warm, 1, 1),
    gradient("cool", cool), gradient("cool-diag", cool, 1, 1),
    gradient("off", [(0, "#FFFFFF"), (1, "#FFFFFF")]), gradient("off-diag", [(0, "#FFFFFF"), (1, "#FFFFFF")], 1, 1),
    gradient("orb", [(0, "#FFD66B"), (0.55, "#FF7A59"), (1, "#E24FD3")], 1, 1),
    '<filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/></filter>',
    '<filter id="panel-shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#000" flood-opacity="0.55"/></filter>',
    '<filter id="knob" x="-50%" y="-50%" width="200%" height="200%"><feDropShadow dx="0" dy="1" stdDeviation="1.2" flood-color="#000" flood-opacity="0.35"/></filter>',
    '<filter id="soft" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="10"/></filter>',
])

# Background, glows and grain
parts = [
    f'<rect width="{W}" height="{H}" fill="url(#bg)"/>',
    '<ellipse cx="300" cy="330" rx="430" ry="380" fill="url(#glow-amber)"/>',
    '<ellipse cx="960" cy="150" rx="420" ry="320" fill="url(#glow-pink)"/>',
    '<ellipse cx="1120" cy="620" rx="460" ry="360" fill="url(#glow-blue)"/>',
    f'<rect width="{W}" height="{H}" filter="url(#grain)" opacity="0.05"/>',
]

# Menu bar strip
bar_h = 34
parts += [
    f'<rect width="{W}" height="{bar_h}" fill="#FFFFFF" fill-opacity="0.07"/>',
    f'<rect y="{bar_h}" width="{W}" height="1" fill="#FFFFFF" fill-opacity="0.08"/>',
]
bulb_x = 968
parts += [
    f'<rect x="{bulb_x - 9}" y="5" width="36" height="24" rx="6" fill="#FFFFFF" fill-opacity="0.16"/>',
    f'<circle cx="{bulb_x + 9}" cy="17" r="11" fill="#FFB86B" opacity="0.55" filter="url(#soft)"/>',
    icon("lightbulb", "fill", bulb_x, 8, 18, "#FFFFFF"),
    icon("magnifying-glass", "bold", 1018, 9, 16, "#FFFFFF", 0.8),
    icon("wifi-high", "bold", 1052, 8, 18, "#FFFFFF", 0.8),
    icon("battery-high", "fill", 1088, 8, 20, "#FFFFFF", 0.8),
    text(1214, 22, "Mon 12 Oct  9:41", 13, 500, "#FFFFFF", anchor="end", extra='fill-opacity="0.85"'),
]

# Menu panel hanging from the bulb
px, py, pw, ph = 800, 52, 380, 520
parts += [
    f'<g filter="url(#panel-shadow)"><rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="18" fill="#1C1A29" fill-opacity="0.94"/></g>',
    f'<rect x="{px + 0.5}" y="{py + 0.5}" width="{pw - 1}" height="{ph - 1}" rx="17.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.12"/>',
]
hx, hy = px + 16, py + 16
parts += [
    f'<circle cx="{hx + 20}" cy="{hy + 20}" r="22" fill="url(#orb)" opacity="0.7" filter="url(#soft)"/>',
    f'<circle cx="{hx + 20}" cy="{hy + 20}" r="20" fill="url(#orb)"/>',
    icon("lightbulb", "fill", hx + 10, hy + 10, 20, "#000000", 0.72),
    text(hx + 54, hy + 17, "Hue Bridge", 15, 600),
    f'<circle cx="{hx + 57}" cy="{hy + 30}" r="3" fill="#34D399"/>',
    text(hx + 65, hy + 34, "5 of 12 lights on", 11.5, 400, "#FFFFFF", extra='fill-opacity="0.55"'),
    f'<circle cx="{px + pw - 33}" cy="{hy + 20}" r="17" fill="url(#orb)"/>',
    icon("power", "bold", px + pw - 41, hy + 12, 16, "#000000", 0.72),
    f'<rect x="{px}" y="{py + 72}" width="{pw}" height="1" fill="#FFFFFF" fill-opacity="0.08"/>',
    text(px + 18, py + 98, "ROOMS", 10, 700, "#FFFFFF", spacing=1.2, extra='fill-opacity="0.5"'),
    f'<rect x="{px + 70}" y="{py + 88}" width="16" height="13" rx="6.5" fill="#FFFFFF" fill-opacity="0.08"/>',
    text(px + 78, py + 98, "3", 9, 700, "#FFFFFF", anchor="middle", extra='fill-opacity="0.5"'),
]
cx, cw = px + 12, pw - 24
parts += [
    card(cx, py + 110, cw, "Living room", "All 4 on", "couch", "warm", True, 72),
    card(cx, py + 218, cw, "Office", "2 of 3 on", "desktop", "cool", True, 45),
    card(cx, py + 326, cw, "Bedroom", "Off", "bed", "off", False, 0),
]
# Scene chips peeking under the cards, then the footer
sy = py + 438
chips = [("Relax", True), ("Concentrate", False), ("Nightlight", False)]
chip_x = cx
for label, active in chips:
    width = 26 + len(label) * 6.6
    fill = 'url(#warm)' if active else "#FFFFFF"
    op = 1 if active else 0.07
    tf, top = ("#000000", 0.72) if active else ("#FFFFFF", 0.85)
    parts += [
        f'<rect x="{chip_x}" y="{sy}" width="{width:.0f}" height="24" rx="12" fill="{fill}" fill-opacity="{op}"/>',
        icon("sparkle", "fill" if active else "regular", chip_x + 9, sy + 6.5, 11, tf, top),
        text(chip_x + 24, sy + 16, label, 11, 500, tf, extra=f'fill-opacity="{top}"'),
    ]
    chip_x += width + 6
parts += [
    f'<rect x="{px}" y="{py + ph - 44}" width="{pw}" height="1" fill="#FFFFFF" fill-opacity="0.08"/>',
    icon("gear-six", "regular", px + 18, py + ph - 31, 18, "#FFFFFF", 0.55),
    icon("arrows-clockwise", "regular", px + 48, py + ph - 31, 18, "#FFFFFF", 0.55),
    text(px + pw - 18, py + ph - 17, "Quit", 12, 400, "#FFFFFF", anchor="end", extra='fill-opacity="0.55"'),
]

# Left: logo, wordmark, tagline, install command
lx = 84
parts += [
    logo(lx - 22, 112, 168),
    f'<text x="{lx - 4}" y="372" font-family="Inter" font-size="104" font-weight="800" letter-spacing="-3">'
    '<tspan fill="url(#title)">Hue</tspan><tspan fill="#FFFFFF">Bar</tspan></text>',
    text(lx, 426, "Control your Philips Hue lights", 30, 500, "#FFFFFF", extra='fill-opacity="0.82"'),
    text(lx, 466, "from the macOS menu bar.", 30, 500, "#FFFFFF", extra='fill-opacity="0.82"'),
]
cmd = "brew install --cask dirien/dirien/huebar"
cmd_w = 40 + len(cmd) * 10.8
parts += [
    f'<rect x="{lx}" y="510" width="{cmd_w:.0f}" height="46" rx="12" fill="#000000" fill-opacity="0.35"/>',
    f'<rect x="{lx + 0.5}" y="510.5" width="{cmd_w - 1:.0f}" height="45" rx="11.5" fill="none" stroke="#FFFFFF" stroke-opacity="0.12"/>',
    text(lx + 18, 539, "$", 18, 600, "#FFB86B", family="JetBrains Mono"),
    text(lx + 38, 539, cmd, 18, 500, "#FFFFFF", family="JetBrains Mono", extra='fill-opacity="0.92"'),
    text(lx, 600, "github.com/dirien/huebar", 17, 500, "#FFFFFF", extra='fill-opacity="0.5"'),
]

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
       f'<title>HueBar: control your Philips Hue lights from the macOS menu bar</title>'
       f'<defs>{defs}</defs>{"".join(parts)}</svg>\n')
OUT.write_text(svg)
subprocess.run(["rsvg-convert", str(OUT), "-o", str(OUT.with_suffix(".png"))], check=True)
print(f"Wrote {OUT.relative_to(ROOT)} and {OUT.with_suffix('.png').relative_to(ROOT)}")
