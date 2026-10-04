#!/bin/bash
# Explicitly invoked only: uploads the signed app to Apple's notarization service.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ALTWINDOW_SIGNING_IDENTITY:?Set your Developer ID Application signing identity}"
: "${ALTWINDOW_NOTARY_PROFILE:?Set a configured notarytool keychain profile}"
: "${ALTWINDOW_BUNDLE_ID:?Set your stable publisher-owned bundle identifier}"
if [[ "$ALTWINDOW_SIGNING_IDENTITY" != "Developer ID Application:"* || "$ALTWINDOW_BUNDLE_ID" == local.* ]]; then
    echo 'Release requires a Developer ID Application identity and a non-local bundle identifier.' >&2
    exit 1
fi
mkdir -p release
export ALTWINDOW_APP_PATH="$PWD/release/AltWindow.app"
bash build.sh
ARCHIVE="$PWD/release/AltWindow.zip"
ditto -c -k --sequesterRsrc --keepParent "$ALTWINDOW_APP_PATH" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$ALTWINDOW_NOTARY_PROFILE" --wait
xcrun stapler staple "$ALTWINDOW_APP_PATH"
xcrun stapler validate "$ALTWINDOW_APP_PATH"
codesign --verify --deep --strict "$ALTWINDOW_APP_PATH"
spctl --assess --type execute --verbose=2 "$ALTWINDOW_APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$ALTWINDOW_APP_PATH" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Release artifact: $ARCHIVE"
