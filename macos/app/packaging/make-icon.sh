#!/bin/bash
# SPDX-License-Identifier: MIT
# Build AppIcon.icns from the Xerotier favicon (packaging/xerotier-favicon.svg,
# from https://xerotier.ai/favicon.svg). The SVG is rasterized crisply at 1024
# via a tiny compiled Swift helper (NSImage), then downsampled to the iconset.
# Usage: make-icon.sh <out.icns>
set -euo pipefail

OUT="${1:?usage: make-icon.sh <out.icns>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/xerotier-favicon.svg"
[ -f "$SRC" ] || { echo "missing logo at $SRC"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Theme the favicon's background to the Xerotier warm cream (#FFF5EE, the
# background of the official PNG mark) instead of its plain white, leaving the
# downloaded SVG pristine.
BG="${ICON_BG:-#FFF5EE}"
sed "s/fill=\"#fff\"/fill=\"$BG\"/" "$SRC" > "$TMP/themed.svg"

# Rasterize the vector at full resolution (compiled — `swift` immediate mode
# can't JIT-link AppKit).
swiftc -O -framework AppKit -o "$TMP/make-icon" "$HERE/make-icon.swift"
"$TMP/make-icon" "$TMP/themed.svg" "$TMP/master.png" 1024 >/dev/null

ICONSET="$TMP/Xerotier.iconset"
mkdir -p "$ICONSET"
sizes=(
  "16:icon_16x16.png"        "32:icon_16x16@2x.png"
  "32:icon_32x32.png"        "64:icon_32x32@2x.png"
  "128:icon_128x128.png"     "256:icon_128x128@2x.png"
  "256:icon_256x256.png"     "512:icon_256x256@2x.png"
  "512:icon_512x512.png"     "1024:icon_512x512@2x.png"
)
for entry in "${sizes[@]}"; do
  px="${entry%%:*}"; name="${entry##*:}"
  sips -z "$px" "$px" "$TMP/master.png" --out "$ICONSET/$name" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
