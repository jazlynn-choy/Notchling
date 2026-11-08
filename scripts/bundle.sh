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
swift build -c release --product notch
BIN_DIR=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Notchling" "$APP/Contents/MacOS/Notchling"
# The `notch` command ships inside the app; Settings symlinks it onto the PATH.
cp "$BIN_DIR/notch" "$APP/Contents/MacOS/notch"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

DEV_IDENTITY="Notchling Dev"
# Nested code is signed first, then the app around it (codesign rejects the reverse).
sign() {
    codesign --force "$@" "$APP/Contents/MacOS/notch"
    codesign --force "$@" "$APP"
}
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    sign --options runtime --timestamp --sign "$SIGN_IDENTITY"
elif security find-certificate -c "$DEV_IDENTITY" >/dev/null 2>&1; then
    sign --timestamp=none --sign "$DEV_IDENTITY"
else
    sign --sign -
    echo "warning: ad-hoc signed, so macOS will ask for permissions again after every build." >&2
    echo "         Create a \"$DEV_IDENTITY\" certificate once to fix that (see README)." >&2
fi
echo "Built $APP (v$VERSION, build $BUILD)"
