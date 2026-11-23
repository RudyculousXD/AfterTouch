#!/bin/bash
# Re-signs, notarises and staples the .dmg. Requires a Developer ID Application certificate
# and a notarytool keychain profile. Not usable until those exist — see README.
#
#   xcrun notarytool store-credentials "nocta" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPER_ID:?Set DEVELOPER_ID, e.g. 'Developer ID Application: Your Name (TEAMID)'}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-nocta}"

APP="$ROOT/dist/Nocta.app"
[ -d "$APP" ] || { echo "No app at $APP — run Scripts/build.sh first."; exit 1; }

echo "==> Signing with Hardened Runtime"
# --deep is deprecated; sign nested code first, then the app itself.
find "$APP/Contents/Frameworks" -name "*.framework" -maxdepth 1 2>/dev/null | while read -r fw; do
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$fw"
done
codesign --force --timestamp --options runtime \
  --entitlements "$ROOT/Resources/Nocta.entitlements" \
  --sign "$DEVELOPER_ID" "$APP"

codesign --verify --strict --verbose=2 "$APP"

echo "==> Rebuilding the disk image with the signed app"
"$ROOT/Scripts/package-dmg.sh"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Nocta-$VERSION.dmg"

echo "==> Submitting for notarisation (this can take several minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Notarised: $DMG"
