#!/bin/zsh
# Builds Notchling.app next to this script.
set -e
cd "$(dirname "$0")"
APP=Notchling.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 Sources/*.swift -o "$APP/Contents/MacOS/Notchling"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Notchling</string>
    <key>CFBundleIdentifier</key><string>local.notchling</string>
    <key>CFBundleExecutable</key><string>Notchling</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSRemindersFullAccessUsageDescription</key><string>Notchling shows your reminders in the notch and lets you add and tick them off.</string>
    <key>NSRemindersUsageDescription</key><string>Notchling shows your reminders in the notch and lets you add and tick them off.</string>
    <key>NSAppleEventsUsageDescription</key><string>Notchling shows and controls what's playing in Music or Spotify.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
