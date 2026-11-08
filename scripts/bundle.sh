#!/bin/zsh
# Builds a release binary and wraps it in Notchling.app.
#
#   scripts/bundle.sh                 # ad-hoc signed, for running locally
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh   # for distribution
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
VERSION=${VERSION:-0.1.0}
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/Notchling.app

swift build -c release --product Notchling
BIN=$(swift build -c release --show-bin-path)/Notchling

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Notchling"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP (v$VERSION, build $BUILD)"
