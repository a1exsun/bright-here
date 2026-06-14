#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

if [[ ! -x "$SPARKLE_TOOLS_DIR/generate_appcast" ]]; then
  echo "Sparkle tools are missing. Run 'swift package resolve' first." >&2
  exit 1
fi

rm -f "$ROOT_DIR/release/appcast.xml"
"$SPARKLE_TOOLS_DIR/generate_appcast" \
  --account bright-here \
  --download-url-prefix "https://github.com/a1exsun/bright-here/releases/download/v$VERSION/" \
  "$ROOT_DIR/release"
cp "$ROOT_DIR/release/appcast.xml" "$ROOT_DIR/release/appcast"
