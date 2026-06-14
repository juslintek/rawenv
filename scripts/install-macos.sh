#!/usr/bin/env bash
# install-macos.sh — Build the latest rawenv CLI + Rawenv.app and install them
# locally on this Mac.
#
#   • CLI   → ~/.rawenv/bin/rawenv   (add ~/.rawenv/bin to PATH)
#   • App   → /Applications/Rawenv.app
#
# Safe re-install: kills any running instance and clears macOS saved-application
# state first, so a previously-crashed app is never restored into a loop.
#
# Usage:
#   scripts/install-macos.sh [version]
#
# Env:
#   INSTALL_CLI_DIR   override CLI install dir (default: ~/.rawenv/bin)
#   SKIP_APP=1        build/install the CLI only (skip the .app)
#   DEVELOPER_ID_APP  Developer ID identity for real signing (optional)
set -euo pipefail

VERSION="${1:-0.2.0}"
BUNDLE_ID="io.rawenv.app"
APP_NAME="Rawenv.app"
INSTALL_CLI_DIR="${INSTALL_CLI_DIR:-$HOME/.rawenv/bin}"
APPLICATIONS_DIR="/Applications"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS_DIR="${REPO_ROOT}/gui/macos"

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die() {
  printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# 0. Pre-flight: confirm toolchain.
# ---------------------------------------------------------------------------
command -v zig >/dev/null || die "zig not found in PATH (need Zig 0.16.0+)"
[ "$(uname -s)" = "Darwin" ] || die "this installer targets macOS"

# ---------------------------------------------------------------------------
# 1. Stop any running instance and clear restored state (breaks crash loops).
# ---------------------------------------------------------------------------
log "Stopping any running Rawenv instance…"
pkill -9 -x Rawenv 2>/dev/null || true
pkill -9 -f "${APP_NAME}/Contents/MacOS/Rawenv" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Build the release CLI and install it.
# ---------------------------------------------------------------------------
log "Building rawenv CLI ${VERSION} (ReleaseSafe)…"
zig build -Doptimize=ReleaseSafe -Dversion="$VERSION"
CLI_BIN="${REPO_ROOT}/zig-out/bin/rawenv"
[ -x "$CLI_BIN" ] || die "CLI build failed: $CLI_BIN not found"

log "Installing CLI → ${INSTALL_CLI_DIR}/rawenv"
mkdir -p "$INSTALL_CLI_DIR"
install -m 0755 "$CLI_BIN" "${INSTALL_CLI_DIR}/rawenv"

# Hash check: the installed CLI must be byte-identical to what we just built.
SRC_SHA="$(shasum -a 256 "$CLI_BIN" | awk '{print $1}')"
DST_SHA="$(shasum -a 256 "${INSTALL_CLI_DIR}/rawenv" | awk '{print $1}')"
[ "$SRC_SHA" = "$DST_SHA" ] || die "CLI hash mismatch after install (src ${SRC_SHA:0:12} != dst ${DST_SHA:0:12})"
echo "    $("${INSTALL_CLI_DIR}/rawenv" --version) installed  (sha256 ${DST_SHA:0:12}… verified)"

# PATH hint
case ":${PATH}:" in
  *":${INSTALL_CLI_DIR}:"*) ;;
  *)
    warn "${INSTALL_CLI_DIR} is not in your PATH. Add to ~/.zshrc:"
    printf '         export PATH="%s:$PATH"\n' "$INSTALL_CLI_DIR"
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Build and install the .app (unless SKIP_APP=1).
# ---------------------------------------------------------------------------
if [ "${SKIP_APP:-0}" = "1" ]; then
  log "SKIP_APP=1 — done (CLI only)."
  exit 0
fi

command -v xcodebuild >/dev/null || die "xcodebuild not found — install Xcode, or run with SKIP_APP=1 for CLI only"

log "Building & signing ${APP_NAME}…"
APP_PATH="$(APP_VERSION="$VERSION" CLI_BINARY="$CLI_BIN" \
  bash "${MACOS_DIR}/scripts/build-app.sh" | tail -1)"
[ -d "$APP_PATH" ] || die "build-app.sh did not produce an .app ($APP_PATH)"

# Sanity check: the embedded CLI must NOT be the GUI binary (guards the
# case-insensitive self-exec bug that flooded the Dock).
EMBEDDED="${APP_PATH}/Contents/Resources/rawenv"
[ -x "$EMBEDDED" ] || die "embedded CLI missing at ${EMBEDDED}"
if cmp -s "${APP_PATH}/Contents/MacOS/Rawenv" "$EMBEDDED"; then
  die "embedded CLI is identical to the GUI binary — refusing to install (self-exec risk)"
fi

log "Installing app → ${APPLICATIONS_DIR}/${APP_NAME}"
rm -rf "${APPLICATIONS_DIR:?}/${APP_NAME}"
cp -R "$APP_PATH" "${APPLICATIONS_DIR}/${APP_NAME}"

# Hash check: the installed app's GUI binary + embedded CLI must match the build.
for rel in "Contents/MacOS/Rawenv" "Contents/Resources/rawenv"; do
  src_sha="$(shasum -a 256 "${APP_PATH}/${rel}" | awk '{print $1}')"
  dst_sha="$(shasum -a 256 "${APPLICATIONS_DIR}/${APP_NAME}/${rel}" | awk '{print $1}')"
  [ "$src_sha" = "$dst_sha" ] || die "app hash mismatch for ${rel} (src ${src_sha:0:12} != dst ${dst_sha:0:12})"
  echo "    ${rel}  sha256 ${dst_sha:0:12}… verified"
done

# Strip the quarantine flag so Gatekeeper does not block a locally-built,
# unsigned/ad-hoc app on first launch.
xattr -dr com.apple.quarantine "${APPLICATIONS_DIR}/${APP_NAME}" 2>/dev/null || true

log "Done."
echo ""
echo "  CLI:  ${INSTALL_CLI_DIR}/rawenv"
echo "  App:  ${APPLICATIONS_DIR}/${APP_NAME}"
echo ""
echo "  Launch:  open -a Rawenv"
