#!/bin/bash
# Packages dist/Nocta.app into a distributable .dmg using hdiutil (no extra tooling).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
APP="$DIST/Nocta.app"
[ -d "$APP" ] || { echo "No app at $APP — run Scripts/build.sh first."; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$DIST/Nocta-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Staging disk image contents"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/README.md" "$STAGE/README.md" 2>/dev/null || true

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Nocta" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "==> Verifying"
hdiutil verify "$DMG" >/dev/null && echo "    image verified"
shasum -a 256 "$DMG" | sed 's/^/    /'

echo
echo "Packaged: $DMG"
echo
echo "NOTE: this build is ad-hoc signed (no Developer ID on this machine), so Gatekeeper"
echo "      will block a double-click. Users must right-click the app and choose Open once."
echo "      Run Scripts/notarize.sh once you have a Developer ID certificate."
