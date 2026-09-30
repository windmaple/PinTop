#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building PinTop..."
swift build -c release

APP_DIR="$SCRIPT_DIR/PinTop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/PinTop" "$MACOS_DIR/PinTop"
cp "Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
chmod +x "$MACOS_DIR/PinTop"

# Ad-hoc sign with consistent bundle identifier so macOS TCC permissions work cleanly
codesign --force --deep --sign - --identifier "com.pintop.mac" "$APP_DIR"

echo "✅ Packaged $APP_DIR"
