#!/bin/bash
# SPDX-License-Identifier: MIT
# Package dist/Xerotier.app into a drag-to-install DMG, and (if credentials are
# present) notarize + staple it.
#
# Env:
#   VERSION         marketing version (default 0.1.0), used for the volume name.
#   NOTARY_PROFILE  name of a stored `notarytool store-credentials` keychain
#                   profile. If set, the DMG is submitted, awaited, and stapled.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/.." && pwd)"
DIST="$APP_ROOT/dist"
APP="$DIST/Xerotier.app"
VERSION="${VERSION:-0.1.0}"
DMG="$DIST/Xerotier-$VERSION.dmg"

[ -d "$APP" ] || { echo "build the app first: packaging/build-app.sh"; exit 1; }

echo "==> staging DMG contents"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create $DMG"
rm -f "$DMG"
hdiutil create -volname "Xerotier $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> notarizing (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  echo "==> notarized + stapled"
else
  echo "==> NOTARY_PROFILE not set; DMG is unsigned/un-notarized (local use only)"
fi

echo "==> created $DMG"
