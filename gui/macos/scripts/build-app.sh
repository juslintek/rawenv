#!/usr/bin/env bash
# Build, embed-the-CLI-into, and code-sign Rawenv.app for Developer ID
# distribution (outside the Mac App Store).
#
# Pipeline:
#   xcodegen generate
#   xcodebuild archive (Release)               -> Rawenv.xcarchive
#   extract Rawenv.app from the archive
#   embed the rawenv CLI binary in Contents/Resources/rawenv
#   deep code-sign (CLI first, then the app) with Hardened Runtime
#   verify (codesign --verify --strict, spctl)
#
# Signing identity is chosen from the environment, with a graceful fallback so
# the script still produces a launchable .app on a machine with no certs (CI
# dev builds, contributor laptops):
#
#   DEVELOPER_ID_APP   "Developer ID Application: Name (TEAMID)"  [optional]
#   DEVELOPMENT_TEAM   Apple Developer Team ID                     [optional]
#   CLI_BINARY         path to the rawenv CLI to embed             [optional]
#   APP_VERSION        marketing version to stamp                  [optional]
#
# If DEVELOPER_ID_APP is unset, the app is ad-hoc signed ("-"). Ad-hoc apps run
# locally but are NOT notarizable — supply a real Developer ID for releases.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/../.." && pwd)"
BUILD_DIR="${MACOS_DIR}/build/developer-id"
ARCHIVE="${BUILD_DIR}/Rawenv.xcarchive"
APP_OUT="${BUILD_DIR}/Rawenv.app"
ENTITLEMENTS="${MACOS_DIR}/Rawenv-DeveloperID.entitlements"

APP_VERSION="${APP_VERSION:-0.2.0}"
CLI_BINARY="${CLI_BINARY:-${REPO_ROOT}/zig-out/bin/rawenv}"
SIGN_ID="${DEVELOPER_ID_APP:-}"

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 0. Resolve a signing identity.
# ---------------------------------------------------------------------------
if [ -z "$SIGN_ID" ]; then
  # Auto-detect the first Developer ID Application identity in the keychain.
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [ -n "$SIGN_ID" ]; then
  log "Signing identity: $SIGN_ID"
  ADHOC=0
else
  warn "No Developer ID Application identity found — falling back to ad-hoc signing."
  warn "The resulting .app will run locally but CANNOT be notarized."
  SIGN_ID="-"
  ADHOC=1
fi

# ---------------------------------------------------------------------------
# 1. Ensure the CLI binary exists, then (re)generate the Xcode project.
# ---------------------------------------------------------------------------
if [ ! -x "$CLI_BINARY" ]; then
  log "CLI binary not found at $CLI_BINARY — building it with zig…"
  (cd "$REPO_ROOT" && zig build -Doptimize=ReleaseSafe -Dversion="$APP_VERSION")
fi
[ -x "$CLI_BINARY" ] || {
  echo "error: rawenv CLI not found at $CLI_BINARY" >&2
  exit 1
}

cd "$MACOS_DIR"
command -v xcodegen >/dev/null && xcodegen generate

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 2. Archive (Release). Defer signing to step 4 so we control the embed order.
# ---------------------------------------------------------------------------
log "Archiving Rawenv (Release)…"
ARCHIVE_ARGS=(
  -project Rawenv.xcodeproj
  -scheme Rawenv
  -configuration Release
  -destination 'generic/platform=macOS'
  -archivePath "$ARCHIVE"
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_ALLOWED=NO
  MARKETING_VERSION="$APP_VERSION"
)
[ -n "${DEVELOPMENT_TEAM:-}" ] && ARCHIVE_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
xcodebuild archive "${ARCHIVE_ARGS[@]}"

ARCHIVED_APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name 'Rawenv.app' | head -1)"
[ -d "$ARCHIVED_APP" ] || {
  echo "error: archive did not produce Rawenv.app" >&2
  exit 1
}
rm -rf "$APP_OUT"
cp -R "$ARCHIVED_APP" "$APP_OUT"

# ---------------------------------------------------------------------------
# 3. Embed the rawenv CLI inside the bundle (Contents/Resources/rawenv).
#    RawenvCLI.candidatePaths() looks here first at runtime.
# ---------------------------------------------------------------------------
log "Embedding CLI: $CLI_BINARY -> Rawenv.app/Contents/Resources/rawenv"
mkdir -p "$APP_OUT/Contents/Resources"
cp "$CLI_BINARY" "$APP_OUT/Contents/Resources/rawenv"
chmod +x "$APP_OUT/Contents/Resources/rawenv"

# ---------------------------------------------------------------------------
# 4. Deep code-sign with the Hardened Runtime. Inner-to-outer: nested
#    frameworks/dylibs and the embedded CLI must be signed before the bundle.
# ---------------------------------------------------------------------------
SIGN_ARGS=(--force --timestamp --options runtime --sign "$SIGN_ID")
if [ "$ADHOC" -eq 1 ]; then
  # --timestamp and Hardened Runtime are meaningless/unsupported for ad-hoc.
  SIGN_ARGS=(--force --sign "-")
fi

# 4a. Nested frameworks and loadable libraries (deepest first).
if [ -d "$APP_OUT/Contents/Frameworks" ]; then
  while IFS= read -r -d '' nested; do
    log "Signing nested: ${nested#$APP_OUT/}"
    codesign "${SIGN_ARGS[@]}" "$nested"
  done < <(find "$APP_OUT/Contents/Frameworks" \( -name '*.framework' -o -name '*.dylib' \) -print0)
fi

# 4b. The embedded CLI.
log "Signing embedded CLI…"
codesign "${SIGN_ARGS[@]}" "$APP_OUT/Contents/Resources/rawenv"

# 4c. The outer app bundle (with entitlements when signing for real).
log "Signing Rawenv.app (Hardened Runtime + entitlements)…"
APP_SIGN_ARGS=("${SIGN_ARGS[@]}")
[ "$ADHOC" -eq 0 ] && APP_SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
codesign "${APP_SIGN_ARGS[@]}" "$APP_OUT"

# ---------------------------------------------------------------------------
# 5. Verify.
# ---------------------------------------------------------------------------
log "Verifying signature…"
codesign --verify --strict --verbose=2 "$APP_OUT" || warn "codesign verify reported issues"
if [ "$ADHOC" -eq 0 ]; then
  spctl --assess --type execute --verbose=2 "$APP_OUT" 2>&1 ||
    warn "spctl assessment failed (expected until the app is notarized & stapled)"
fi

echo ""
log "Built: $APP_OUT"
echo "  Version:  $APP_VERSION"
echo "  Signed:   $([ "$ADHOC" -eq 1 ] && echo 'ad-hoc (not distributable)' || echo "$SIGN_ID")"
echo "  CLI:      Contents/Resources/rawenv ($(du -h "$APP_OUT/Contents/Resources/rawenv" | awk '{print $1}'))"
echo "$APP_OUT"
