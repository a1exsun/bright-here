#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${BRIGHT_HERE_SIGN_IDENTITY:-Bright Here Self-Signed Code Signing}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
DAYS="${SELF_SIGNED_CERT_DAYS:-3650}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$ROOT_DIR/.build/signing"
EXPORT_P12_PATH="${EXPORT_P12_PATH:-$EXPORT_DIR/bright-here-signing.p12}"
P12_PASSWORD_PATH="${P12_PASSWORD_PATH:-$EXPORT_DIR/bright-here-signing.password}"
P12_PASSWORD="${P12_PASSWORD:-}"

if security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -F "\"$IDENTITY_NAME\"" >/dev/null; then
  echo "Code signing identity already exists: $IDENTITY_NAME"
  if [[ -f "$EXPORT_P12_PATH" ]]; then
    echo "Existing exported identity: $EXPORT_P12_PATH"
  else
    echo "No exported .p12 was created by this script. Reuse the existing Keychain identity locally, or export it manually from Keychain Access for CI." >&2
  fi
  exit 0
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bright-here-signing.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

KEY_PATH="$TMP_DIR/identity.key"
CERT_PATH="$TMP_DIR/identity.crt"
P12_PATH="$TMP_DIR/identity.p12"

if [[ -z "$P12_PASSWORD" ]]; then
  if [[ -f "$P12_PASSWORD_PATH" ]]; then
    P12_PASSWORD="$(tr -d '\n' < "$P12_PASSWORD_PATH")"
  else
    P12_PASSWORD="$(openssl rand -hex 24)"
  fi
fi

openssl req \
  -x509 \
  -newkey rsa:3072 \
  -sha256 \
  -nodes \
  -days "$DAYS" \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -subj "/CN=$IDENTITY_NAME/O=Bright Here/OU=Bright Here/" \
  -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$KEY_PATH" \
  -in "$CERT_PATH" \
  -name "$IDENTITY_NAME" \
  -out "$P12_PATH" \
  -passout "pass:$P12_PASSWORD" \
  >/dev/null 2>&1

security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN_PATH" \
  "$CERT_PATH" \
  >/dev/null

mkdir -p "$(dirname "$EXPORT_P12_PATH")" "$(dirname "$P12_PASSWORD_PATH")"
cp "$P12_PATH" "$EXPORT_P12_PATH"
printf '%s\n' "$P12_PASSWORD" > "$P12_PASSWORD_PATH"
chmod 600 "$EXPORT_P12_PATH" "$P12_PASSWORD_PATH"

echo "Created code signing identity: $IDENTITY_NAME"
echo "Exported signing identity to: $EXPORT_P12_PATH"
echo "Saved P12 password to: $P12_PASSWORD_PATH"
echo "Keep both files private. Use the same .p12 for future release signing."

security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "\"$IDENTITY_NAME\"" || {
  echo "Created identity, but macOS did not report it as a valid code signing identity." >&2
  exit 1
}
