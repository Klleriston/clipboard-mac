#!/usr/bin/env bash
# Wraps the SwiftPM binary in a .app bundle. The bundle is required for two
# reasons: LSUIElement (no Dock icon) and a stable identity for the
# Accessibility permission granted in System Settings.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-debug}"

swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/macUtil"
APP="build/macUtil.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/macUtil"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature with a fixed identifier so macOS keeps recognising the app
# across rebuilds.
codesign --force --sign - --identifier dev.macutil.app "$APP"

echo "built $APP"
