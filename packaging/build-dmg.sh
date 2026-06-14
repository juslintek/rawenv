#!/usr/bin/env bash
# Build a distributable macOS DMG for rawenv.
#
# Produces a code-signed, notarized (when credentials are available) Rawenv.app
# inside a drag-to-install DMG. The .app embeds the rawenv CLI binary so it is
# fully self-contained.
#
# Usage: packaging/build-dmg.sh [version]
#
# Signing / notarization are driven by environment variables (see
# gui/macos/scripts/build-app.sh and notarize.sh). With no credentials the DMG
# is still produced with an ad-hoc-signed app for local testing.
set -euo pipefail

VERSION="${1:-0.2.0}"
ARCH="$(uname -m)"
DMG_NAME="rawenv-${VERSION}-${ARCH}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_DIR="${REPO_ROOT}/gui/macos"
STAGE_DIR="/tmp/rawenv-dmg-build"
DMG_PATH="${REPO_ROOT}/packaging/${DMG_NAME}.dmg"

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

cd "$REPO_ROOT"
log "Building rawenv ${VERSION} DMG for ${ARCH}…"

# ---------------------------------------------------------------------------
# 1. Build the release CLI binary (embedded in the app + shipped standalone).
# ---------------------------------------------------------------------------
log "Building release CLI…"
zig build -Doptimize=ReleaseSafe -Dversion="$VERSION"
CLI_BINARY="${REPO_ROOT}/zig-out/bin/rawenv"
[ -x "$CLI_BINARY" ] || {
  echo "error: CLI build failed ($CLI_BINARY)" >&2
  exit 1
}
echo "  CLI: $(ls -lh "$CLI_BINARY" | awk '{print $5}')"

# ---------------------------------------------------------------------------
# 2. Build, embed-CLI-into, and sign Rawenv.app (Developer ID, hardened runtime).
# ---------------------------------------------------------------------------
log "Building & signing Rawenv.app…"
APP_PATH="$(APP_VERSION="$VERSION" CLI_BINARY="$CLI_BINARY" \
  bash "${MACOS_DIR}/scripts/build-app.sh" | tail -1)"
[ -d "$APP_PATH" ] || {
  echo "error: build-app.sh did not produce an .app ($APP_PATH)" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 3. Stage DMG contents: Rawenv.app + /Applications symlink + standalone CLI.
# ---------------------------------------------------------------------------
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/Rawenv.app"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$STAGE_DIR/rawenv (CLI only)"
cp "$CLI_BINARY" "$STAGE_DIR/rawenv (CLI only)/rawenv"
chmod +x "$STAGE_DIR/rawenv (CLI only)/rawenv"
cat >"$STAGE_DIR/rawenv (CLI only)/README.txt" <<'README'
Rawenv.app already bundles this CLI — just drag Rawenv.app to Applications.

To install ONLY the command-line tool:
  mkdir -p ~/.rawenv/bin
  cp rawenv ~/.rawenv/bin/
  echo 'export PATH="$HOME/.rawenv/bin:$PATH"' >> ~/.zshrc
README

# ---------------------------------------------------------------------------
# 4. Create the compressed DMG.
# ---------------------------------------------------------------------------
mkdir -p "${REPO_ROOT}/packaging"
rm -f "$DMG_PATH"
log "Creating DMG…"
hdiutil create \
  -volname "rawenv ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGE_DIR"

# ---------------------------------------------------------------------------
# 5. Sign the DMG itself (Developer ID), then notarize + staple.
# ---------------------------------------------------------------------------
SIGN_ID="${DEVELOPER_ID_APP:-}"
[ -z "$SIGN_ID" ] && SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null |
  sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
if [ -n "$SIGN_ID" ]; then
  log "Signing DMG with $SIGN_ID…"
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG_PATH"
else
  warn "No Developer ID identity — DMG left unsigned (local build)."
fi

log "Notarizing DMG…"
bash "${MACOS_DIR}/scripts/notarize.sh" "$DMG_PATH" || warn "notarization step did not complete"

echo ""
log "DMG ready: $DMG_PATH"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
