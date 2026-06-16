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

- Keep the brightness HUD title text and filled slider track permanently white in both light and dark appearances.
- Use ad-hoc signing for public release artifacts until Developer ID signing is available.

## Install

Download \`BrightHere-$VERSION.dmg\`, open it, then drag \`Bright Here.app\` to Applications.

This release is ad-hoc signed and not notarized with Apple Developer ID. macOS may still show an unidentified developer warning on first install.

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
