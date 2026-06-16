#!/usr/bin/env bash

DEFAULT_SIGN_IDENTITY="Bright Here Self-Signed Code Signing"

resolve_sign_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$SIGN_IDENTITY"
    return
  fi

  local candidate="${BRIGHT_HERE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
  if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$candidate\"" >/dev/null; then
    printf '%s\n' "$candidate"
  else
    printf '%s\n' "-"
  fi
}

print_sign_identity_summary() {
  local identity="$1"
  if [[ "$identity" == "-" ]]; then
    echo "Signing with ad-hoc identity. Run Scripts/create_self_signed_identity.sh for stable local signing." >&2
  else
    echo "Signing with identity: $identity" >&2
  fi
}
