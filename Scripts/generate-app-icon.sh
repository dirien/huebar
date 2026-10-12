#!/usr/bin/env bash
# Renders assets/logo.svg into Resources/AppIcon.icns. Needs librsvg (`brew install librsvg`) and iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" assets/logo.svg -o "$iconset/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) assets/logo.svg -o "$iconset/icon_${size}x${size}@2x.png"
done
iconutil --convert icns --output Resources/AppIcon.icns "$iconset"
echo "Wrote Resources/AppIcon.icns"
