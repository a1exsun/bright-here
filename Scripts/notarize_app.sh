#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Skipping notarization: APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD are required."
  exit 0
fi

ZIP_PATH="${1:?Usage: Scripts/notarize_app.sh path/to/BrightHere.zip}"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

APP_DIR="$(dirname "$ZIP_PATH")/Bright Here.app"
if [[ -d "$APP_DIR" ]]; then
  xcrun stapler staple "$APP_DIR"
fi
