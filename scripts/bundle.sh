#!/bin/zsh
# Builds a release binary and wraps it in Notchling.app.
#
#   scripts/bundle.sh       # signed with the local "Notchling Dev" certificate if you have one
#   SIGN_IDENTITY="Developer ID Application: …" scripts/bundle.sh   # for distribution
#
# Why the local certificate matters: macOS ties privacy permissions (Reminders, Calendar,
# Automation) to the app's signature. An ad-hoc signature changes on every build, so each
# rebuild looks like a new app and permissions have to be granted again. Signing with the
# same certificate every time keeps them. See "Keep permissions between builds" in the README.
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

DEV_IDENTITY="Notchling Dev"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
elif security find-certificate -c "$DEV_IDENTITY" >/dev/null 2>&1; then
    codesign --force --timestamp=none --sign "$DEV_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
    echo "warning: ad-hoc signed, so macOS will ask for permissions again after every build." >&2
    echo "         Create a \"$DEV_IDENTITY\" certificate once to fix that (see README)." >&2
fi
echo "Built $APP (v$VERSION, build $BUILD)"
