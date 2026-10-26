#!/bin/bash
# Build and install into /Applications, then open it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build_app.sh"

TARGET_DIR="/Applications"
if [[ ! -w "$TARGET_DIR" ]]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi

DEST="$TARGET_DIR/净卸.app"
rm -rf "$DEST"
ditto "$ROOT/dist/净卸.app" "$DEST"
xattr -cr "$DEST"

echo "==> 已安装：$DEST"
open "$DEST"
