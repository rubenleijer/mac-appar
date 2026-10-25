#!/bin/bash
# Builds "build/Dynamic Island.app". Usage: [CONFIG=debug] ./build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Dynamic Island.app"
CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/arm64-apple-macosx/$CONFIG/DynamicIsland" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Scripts/update.sh "$APP/Contents/Resources/"
# The commit this was built from, so the app can tell when an update is out.
COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Add :DIGitCommit string $COMMIT" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true

clang -fobjc-arc -O2 -dynamiclib -mmacosx-version-min=14.0 -framework Foundation \
    -o "$APP/Contents/Resources/libNowPlayingBridge.dylib" Bridge/NowPlayingBridge.m

# A stable signing identity keeps the Accessibility permission across rebuilds;
# without one the app is signed ad hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libNowPlayingBridge.dylib"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"

if [ "${1:-}" = "--run" ]; then
    pkill -x DynamicIsland 2>/dev/null || true
    sleep 0.3
    open "$APP"
fi
