#!/bin/bash
# Builds Nocta.app into ./dist. Regenerates the Xcode project first so project.yml
# stays the single source of truth.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-Release}"
DIST="$ROOT/dist"

command -v xcodegen >/dev/null || { echo "xcodegen not found. brew install xcodegen"; exit 1; }

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ($CONFIGURATION)"
DERIVED="$ROOT/build/DerivedData"
xcodebuild \
  -project Nocta.xcodeproj \
  -scheme Nocta \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  build | grep -E "error:|warning:|BUILD" || true

APP="$DERIVED/Build/Products/$CONFIGURATION/Nocta.app"
[ -d "$APP" ] || { echo "Build did not produce $APP"; exit 1; }

echo "==> Staging to dist/"
rm -rf "$DIST"
mkdir -p "$DIST"
cp -R "$APP" "$DIST/"

echo "==> Signature"
codesign -dv "$DIST/Nocta.app" 2>&1 | sed 's/^/    /'

echo
echo "Built: $DIST/Nocta.app"
