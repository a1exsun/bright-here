#!/usr/bin/env bash
set -euo pipefail

CERTIFICATE_BASE64="${SIGNING_CERTIFICATE_P12_BASE64:-}"
CERTIFICATE_PASSWORD="${SIGNING_CERTIFICATE_PASSWORD:-}"
IDENTITY_NAME="${SIGN_IDENTITY:-${BRIGHT_HERE_SIGN_IDENTITY:-Bright Here Self-Signed Code Signing}}"

if [[ -z "$CERTIFICATE_BASE64" || -z "$CERTIFICATE_PASSWORD" ]]; then
  echo "Skipping signing identity import: SIGNING_CERTIFICATE_P12_BASE64 and SIGNING_CERTIFICATE_PASSWORD are not configured."
  exit 0
fi

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -hex 24)}"
KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/bright-here-signing.keychain-db"
P12_PATH="${RUNNER_TEMP:-/tmp}/bright-here-signing.p12"
CERT_PATH="${RUNNER_TEMP:-/tmp}/bright-here-signing.crt"

printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$P12_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | sed 's/[ "]//g')
security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN_PATH" > "$CERT_PATH"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$CERT_PATH" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Imported certificate, but identity was not found: $IDENTITY_NAME" >&2
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SIGN_IDENTITY=$IDENTITY_NAME"
    echo "BRIGHT_HERE_SIGN_IDENTITY=$IDENTITY_NAME"
  } >> "$GITHUB_ENV"
fi

echo "Imported signing identity: $IDENTITY_NAME"
