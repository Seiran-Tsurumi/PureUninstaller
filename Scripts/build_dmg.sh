#!/bin/bash
# Create a drag-to-Applications DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build_app.sh"

APP="$ROOT/dist/净卸.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/dist/净卸-1.0.0.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/净卸.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "净卸" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGE"
echo "==> DMG：$DMG"
