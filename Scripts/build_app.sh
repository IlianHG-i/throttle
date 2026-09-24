#!/bin/bash
# Builds RAMBrider.app and signs it, without ever opening Xcode.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RAMBrider"
DISPLAY_NAME="RAM Brider"
BUNDLE_ID="com.ilianhg.RAMBrider"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

echo "==> Compiling (release)"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Pick a real signing identity if one is installed, otherwise fall back to
# an ad-hoc signature (still runs fine locally, just less stable TCC identity).
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+([A-F0-9]+).*/\1/')"

if [ -n "${IDENTITY:-}" ]; then
    echo "==> Signing with identity $IDENTITY"
    codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP_BUNDLE"
else
    echo "==> No Apple Development identity found, signing ad-hoc"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "==> Verifying signature"
codesign --verify --verbose "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
