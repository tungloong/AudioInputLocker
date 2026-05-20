#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="InputSoundMenu"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/InputSoundMenu.app"

xcodebuild \
  -project "$ROOT_DIR/InputSoundMenu.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

pkill -x InputSoundMenu 2>/dev/null || true
open -n "$APP_PATH"

sleep 1
pgrep -fl InputSoundMenu || true
