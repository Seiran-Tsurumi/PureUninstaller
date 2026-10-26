#!/bin/bash
# Build 净卸.app from the Swift Package Manager release binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> 编译 Release（arm64）"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/PureUninstaller"
APP="$ROOT/dist/净卸.app"

if [[ ! -x "$BIN" ]]; then
    echo "找不到编译产物：$BIN" >&2
    exit 1
fi

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PureUninstaller"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/PureUninstaller"

# Prefer a stable identity. TCC (Full Disk Access) binds to the code
# requirement, so re-signing with the same identity keeps the user's grant
# across rebuilds. Ad-hoc signatures change cdhash on every build and would
# invalidate the grant.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(PureUninstaller Local Signing\)".*/\1/p' | head -1)"
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
fi

xattr -cr "$APP"
echo "==> 签名身份：$IDENTITY"
codesign --force --deep --sign "$IDENTITY" "$APP"
xattr -cr "$APP"

if [[ "$IDENTITY" == "-" ]]; then
    echo "警告：没有找到稳定的代码签名身份，当前使用 ad-hoc 签名。"
    echo "      TCC（完全磁盘访问权限）授权会在每次重新打包后失效。"
fi

echo "==> 完成：$APP"
lipo -info "$APP/Contents/MacOS/PureUninstaller" 2>/dev/null || true
