#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Skipping notarization: APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD are required."
  exit 0
fi

SUBMISSION_PATH="${1:?Usage: Scripts/notarize_app.sh path/to/BrightHere.zip-or-dmg}"
APP_DIR="$(dirname "$SUBMISSION_PATH")/Bright Here.app"

if [[ -d "$APP_DIR" ]]; then
  AUTHORITY="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found=1 }')"
  if [[ "$AUTHORITY" != Developer\ ID\ Application:* ]]; then
    echo "Skipping notarization: app is signed with '$AUTHORITY', not Developer ID Application."
    exit 0
  fi
fi

xcrun notarytool submit "$SUBMISSION_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

case "$SUBMISSION_PATH" in
  *.dmg)
    xcrun stapler staple "$SUBMISSION_PATH"
    ;;
  *)
    if [[ -d "$APP_DIR" ]]; then
      xcrun stapler staple "$APP_DIR"
    fi
    ;;
esac
