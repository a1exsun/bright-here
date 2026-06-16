#!/usr/bin/env bash

DEFAULT_SIGN_IDENTITY="Bright Here Self-Signed Code Signing"

resolve_sign_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$SIGN_IDENTITY"
    return
  fi

  if [[ -n "${BRIGHT_HERE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$BRIGHT_HERE_SIGN_IDENTITY"
  else
    printf '%s\n' "-"
  fi
}

print_sign_identity_summary() {
  local identity="$1"
  if [[ "$identity" == "-" ]]; then
    echo "Signing with ad-hoc identity." >&2
  else
    echo "Signing with identity: $identity" >&2
  fi
}
