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

# Sign with a real certificate so the Accessibility grant survives rebuilds.
# An ad-hoc signature's designated requirement is the binary's cdhash, which
# changes on every build and silently invalidates the grant. Override with
# MACUTIL_SIGN_IDENTITY; otherwise the first Apple Development identity in the
# keychain is used, falling back to ad-hoc when none exists.
IDENTITY="${MACUTIL_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "Apple Development:.*/\1/p' | head -n 1)}"
if [[ -z "$IDENTITY" ]]; then
    echo "warning: no signing identity found; using ad-hoc (Accessibility must be re-granted after each build)" >&2
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier dev.macutil.app "$APP"

echo "built $APP"
