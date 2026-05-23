#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="AudioInputLocker"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/AudioInputLocker.app"

xcodebuild \
  -project "$ROOT_DIR/AudioInputLocker.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

pkill -x AudioInputLocker 2>/dev/null || true
pkill -x InputSoundMenu 2>/dev/null || true
open -n "$APP_PATH"

sleep 1
pgrep -fl AudioInputLocker || true
