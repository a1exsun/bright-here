#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
TAG="v$VERSION"
ZIP_PATH="$ROOT_DIR/release/BrightHere-$VERSION.zip"
DMG_PATH="$ROOT_DIR/release/BrightHere-$VERSION.dmg"

ASSETS=("$ZIP_PATH")
if [[ -f "$DMG_PATH" ]]; then
  ASSETS+=("$DMG_PATH")
fi
if [[ -f "$ROOT_DIR/release/appcast" ]]; then
  ASSETS+=("$ROOT_DIR/release/appcast")
fi

RELEASE_NOTES="## What's Changed

- Add a native macOS brightness overlay when F1/F2 changes brightness.
- Replace the overlay progress bar with a draggable native slider and add a setting to show or hide it.
- Improve recovery when the menu bar icon is hidden: launching Bright Here again reopens settings.
- Add a Quit action in settings for users who hide the menu bar icon.
- Hide the debug panel entry from production builds.
- Simplify settings: continuous Step slider and version in the lower-left footer.
- Add stable self-signed signing support for early releases without Developer ID.

## Install

Download \`BrightHere-$VERSION.dmg\`, open it, then drag \`Bright Here.app\` to Applications.

This release is self-signed, not notarized with Apple Developer ID. macOS may still show an unidentified developer warning on first install. After users grant Accessibility once to this stable signing identity, future updates should avoid the repeated-permission problem caused by ad-hoc signing.

The zip asset is kept for Sparkle updates and advanced/manual installs.

## Assets

- \`BrightHere-$VERSION.dmg\`
- \`BrightHere-$VERSION.zip\`
- \`appcast\`"

if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists; uploading release assets with --clobber."
  gh release edit "$TAG" --repo a1exsun/bright-here --notes "$RELEASE_NOTES"
  gh release upload "$TAG" "${ASSETS[@]}" --repo a1exsun/bright-here --clobber
  exit 0
fi

git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" "${ASSETS[@]}" \
  --repo a1exsun/bright-here \
  --title "Bright Here $VERSION" \
  --notes "$RELEASE_NOTES"
