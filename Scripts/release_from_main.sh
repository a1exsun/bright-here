#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
TAG="v$VERSION"
DMG_PATH="$ROOT_DIR/release/BrightHere-$VERSION.dmg"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing release asset: $DMG_PATH" >&2
  exit 1
fi

ASSETS=("$DMG_PATH")
if [[ -f "$ROOT_DIR/release/appcast" ]]; then
  ASSETS+=("$ROOT_DIR/release/appcast")
fi

RELEASE_NOTES="## What's Changed

- Keep the HUD brightness icons permanently white in both light and dark appearances.
- Adjust the HUD glass tint to pure black at 18% opacity.

## Install

Download \`BrightHere-$VERSION.dmg\`, open it, then drag \`Bright Here.app\` to Applications.

This release is ad-hoc signed and not notarized with Apple Developer ID. macOS may still show an unidentified developer warning on first install.

## Assets

- \`BrightHere-$VERSION.dmg\`
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
