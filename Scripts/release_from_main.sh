#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
TAG="v$VERSION"
ZIP_PATH="$ROOT_DIR/release/BrightHere-$VERSION.zip"

if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists; skipping GitHub Release creation."
  exit 0
fi

git tag "$TAG"
git push origin "$TAG"

ASSETS=("$ZIP_PATH")
if [[ -f "$ROOT_DIR/release/appcast.xml" ]]; then
  ASSETS+=("$ROOT_DIR/release/appcast.xml")
fi

gh release create "$TAG" "${ASSETS[@]}" \
  --repo a1exsun/bright-here \
  --title "Bright Here $VERSION" \
  --notes "Automated release for Bright Here $VERSION."
