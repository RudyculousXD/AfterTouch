#!/bin/bash
# Regenerates every icon artefact from Scripts/make-icon.swift, which is the only source
# of truth for the mark. Pass a concept name to switch designs: crescent (default),
# ripple, card.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONCEPT="${1:-crescent}"
SET="Resources/AppIcon.iconset"
APPICON="Resources/Assets.xcassets/AppIcon.appiconset"

echo "==> Rendering '$CONCEPT'"
rm -rf "$SET"
swift Scripts/make-icon.swift "$CONCEPT" "$SET"

echo "==> Asset catalog"
mkdir -p "$APPICON"
rm -f "$APPICON"/*.png
cp "$SET"/*.png "$APPICON"/

echo "==> Nocta.icns"
iconutil --convert icns --output Resources/Nocta.icns "$SET"
rm -rf "$SET"

echo "Done. Rebuild with Scripts/build.sh to pick it up."
