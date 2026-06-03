#!/bin/bash
# SPDX-License-Identifier: MIT
# Build a release Xerotier.app bundle from the SwiftPM executable.
#
# Env:
#   VERSION            marketing version (default 0.1.0)
#   BUILD              build number (default 1)
#   CODESIGN_IDENTITY  signing identity (default "-" = ad-hoc, for local/dev).
#                      Set to a "Developer ID Application: …" identity to make a
#                      notarizable, hardened-runtime build.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/.." && pwd)"   # macos/app
cd "$APP_ROOT"

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"
DIST="$APP_ROOT/dist"
APP="$DIST/Xerotier.app"

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/XerotierAgent"
[ -x "$BIN" ] || { echo "missing built binary at $BIN"; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Xerotier"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@BUILD@/$BUILD/g" \
    "$HERE/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> generating icon"
"$HERE/make-icon.sh" "$APP/Contents/Resources/AppIcon.icns"

echo "==> codesign (identity: $IDENTITY)"
if [ "$IDENTITY" = "-" ]; then
  # Ad-hoc: no hardened runtime / timestamp (those need a real identity).
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "==> built $APP (v$VERSION build $BUILD, signed: $IDENTITY)"
