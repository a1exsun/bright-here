#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
  echo "Skipping notarization: APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD are required."
  exit 0
fi

SUBMISSION_PATH="${1:?Usage: Scripts/notarize_app.sh path/to/BrightHere.zip-or-dmg}"

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
    APP_DIR="$(dirname "$SUBMISSION_PATH")/Bright Here.app"
    if [[ -d "$APP_DIR" ]]; then
      xcrun stapler staple "$APP_DIR"
    fi
    ;;
esac
