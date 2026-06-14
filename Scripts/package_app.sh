#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
SCRATCH_DIR="$ROOT_DIR/.build/apple"
APP_DIR="$ROOT_DIR/release/Bright Here.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

rm -rf "$ROOT_DIR/release"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

swift build -c "$CONFIGURATION" --product bright-here --scratch-path "$SCRATCH_DIR"
swift build -c "$CONFIGURATION" --product bright-here-cli --scratch-path "$SCRATCH_DIR"

BRIGHT_HERE_BIN="$(find "$SCRATCH_DIR" -maxdepth 5 -path "*/$CONFIGURATION/bright-here" -type f -print -quit)"
if [[ -z "$BRIGHT_HERE_BIN" ]]; then
  echo "Could not locate built bright-here executable under $SCRATCH_DIR" >&2
  exit 1
fi
BUILD_DIR="$(dirname "$BRIGHT_HERE_BIN")"

cp "$BUILD_DIR/bright-here" "$MACOS_DIR/bright-here"
cp "$BUILD_DIR/bright-here-cli" "$MACOS_DIR/bright-here-cli"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"

if compgen -G "$BUILD_DIR/*.framework" > /dev/null; then
  cp -R "$BUILD_DIR"/*.framework "$FRAMEWORKS_DIR/"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/bright-here" 2>/dev/null || true

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  find "$FRAMEWORKS_DIR" -maxdepth 1 -name "*.framework" -print0 | while IFS= read -r -d '' framework; do
    codesign --force --deep --sign "$SIGN_IDENTITY" "$framework"
  done
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  find "$FRAMEWORKS_DIR" -maxdepth 1 -name "*.framework" -print0 | while IFS= read -r -d '' framework; do
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$framework"
  done
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

ditto -c -k --norsrc --keepParent "$APP_DIR" "$ROOT_DIR/release/BrightHere-$VERSION.zip"
echo "$ROOT_DIR/release/BrightHere-$VERSION.zip"
