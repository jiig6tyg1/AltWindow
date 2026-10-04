#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${ALTWINDOW_APP_PATH:-$PWD/../AltWindow.app}"
SIGNING_IDENTITY="${ALTWINDOW_SIGNING_IDENTITY:--}"
# Do not silently replace a persistent signing identity with a per-build cdhash.
if [[ "$SIGNING_IDENTITY" == "-" && -d "$APP" ]]; then
    EXISTING_SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
    if [[ "$EXISTING_SIGNATURE" != *"Signature=adhoc"* ]]; then
        echo 'Set ALTWINDOW_SIGNING_IDENTITY to the same certificate used for the installed app. Ad-hoc signing would invalidate privacy permissions.' >&2
        exit 1
    fi
fi
BUILD_DIR="${ALTWINDOW_BUILD_DIR:-$PWD/.build}"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/swift-cache"
swift build --disable-sandbox -c release -debug-info-format none --scratch-path "$BUILD_DIR"
BIN_DIR="$(swift build --disable-sandbox -c release --scratch-path "$BUILD_DIR" --show-bin-path)"
if [[ ! -f Resources/AppIcon.icns || Tools/MakeIcon.swift -nt Resources/AppIcon.icns ]]; then
    swift Tools/MakeIcon.swift "$BUILD_DIR/AppIcon.iconset"
    iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o Resources/AppIcon.icns
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AltWindow" "$APP/Contents/MacOS/AltWindow"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${ALTWINDOW_BUNDLE_ID:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ALTWINDOW_BUNDLE_ID" "$APP/Contents/Info.plist"
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
    TIMESTAMP_OPTION="--timestamp"
    if [[ "${ALTWINDOW_TIMESTAMP:-}" == "none" ]]; then TIMESTAMP_OPTION="--timestamp=none"; fi
    codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" --options runtime "$TIMESTAMP_OPTION" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
