#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0-preview}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData-Release}"
DIST_DIR="${DIST_DIR:-dist}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/AudioInputLocker.app"
ZIP_PATH="$DIST_DIR/AudioInputLocker-$VERSION-macos-arm64.zip"

mkdir -p "$DIST_DIR"

xcodebuild \
  -project AudioInputLocker.xcodeproj \
  -scheme AudioInputLocker \
  -configuration Release \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"
