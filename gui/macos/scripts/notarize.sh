#!/usr/bin/env bash
# Notarize and staple a Developer ID artifact (a .dmg, .zip, or .pkg) with Apple.
#
# Usage: notarize.sh <path-to-artifact>
#
# Credentials come from the environment (never committed). Two options:
#
#   A) A stored notarytool keychain profile (recommended):
#        NOTARY_PROFILE="rawenv-notary"
#      Create it once with:
#        xcrun notarytool store-credentials "rawenv-notary" \
#          --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
#   B) App Store Connect API key OR Apple-ID-per-call:
#        NOTARY_KEY_ID / NOTARY_KEY_ISSUER / NOTARY_KEY_PATH      (API key), or
#        NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD       (app-specific pw)
#
# If no credentials are present the script SKIPS notarization (exit 0) with a
# warning, so `build-dmg.sh` still completes for local/dev builds.
set -euo pipefail

ARTIFACT="${1:-}"
[ -n "$ARTIFACT" ] || { echo "usage: $0 <path-to-dmg|zip|pkg>" >&2; exit 2; }
[ -e "$ARTIFACT" ] || { echo "error: artifact not found: $ARTIFACT" >&2; exit 2; }

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Assemble notarytool auth args from whichever credential set is provided.
# ---------------------------------------------------------------------------
AUTH=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
  AUTH=( --keychain-profile "$NOTARY_PROFILE" )
elif [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_KEY_ISSUER:-}" ] && [ -n "${NOTARY_KEY_PATH:-}" ]; then
  AUTH=( --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_KEY_ISSUER" )
elif [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
  AUTH=( --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" )
else
  warn "No notarization credentials in environment — SKIPPING notarization."
  warn "Set NOTARY_PROFILE (or NOTARY_KEY_* / NOTARY_APPLE_ID+NOTARY_TEAM_ID+NOTARY_PASSWORD) to enable."
  exit 0
fi

# ---------------------------------------------------------------------------
# Submit, wait for Apple's verdict, then staple the ticket to the artifact.
# ---------------------------------------------------------------------------
log "Submitting $ARTIFACT to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ARTIFACT" "${AUTH[@]}" --wait

log "Stapling notarization ticket…"
xcrun stapler staple "$ARTIFACT"

log "Validating staple…"
xcrun stapler validate "$ARTIFACT"

# Gatekeeper acceptance check (best-effort; type depends on artifact).
spctl --assess --type install --verbose=2 "$ARTIFACT" 2>&1 || true

log "Notarized & stapled: $ARTIFACT"
