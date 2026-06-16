#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/signing_identity.sh"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_DIR="$ROOT_DIR/release/Bright Here.app"
DMG_PATH="$ROOT_DIR/release/BrightHere-$VERSION.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"
VOLUME_NAME="Bright Here $VERSION"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  echo "Run Scripts/package_app.sh first." >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/Bright Here.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

SIGN_IDENTITY="$(resolve_sign_identity)"
print_sign_identity_summary "$SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

rm -rf "$STAGING_DIR"
echo "$DMG_PATH"
