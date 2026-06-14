#!/bin/sh
# rawenv installer — downloads the latest release binary for this OS/arch.
set -e

REPO="juslintek/rawenv"
INSTALL_DIR="${RAWENV_INSTALL_DIR:-$HOME/.rawenv}"
BIN_DIR="$INSTALL_DIR/bin"

OS=$(uname -s)
ARCH=$(uname -m)

# Asset names must match what the release workflow publishes:
#   rawenv-<arch>-<os>.tar.gz   (arch: aarch64|x86_64, os: macos|linux)
case "$ARCH" in
  x86_64 | amd64) A="x86_64" ;;
  aarch64 | arm64) A="aarch64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

case "$OS" in
  Linux) ARTIFACT="rawenv-${A}-linux.tar.gz" ;;
  Darwin) ARTIFACT="rawenv-${A}-macos.tar.gz" ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

echo "Installing rawenv ($ARTIFACT)..."
mkdir -p "$BIN_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ARTIFACT"
curl -fsSL "$DOWNLOAD_URL" -o "$TMP/$ARTIFACT"
tar -xzf "$TMP/$ARTIFACT" -C "$TMP"

# The archive contains the bare `rawenv` binary.
if [ -f "$TMP/rawenv" ]; then
  mv "$TMP/rawenv" "$BIN_DIR/rawenv"
else
  find "$TMP" -name rawenv -type f -exec mv {} "$BIN_DIR/rawenv" \;
fi
chmod +x "$BIN_DIR/rawenv"

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo ""
  echo "Add rawenv to your PATH:"
  echo "  export PATH=\"$BIN_DIR:\$PATH\""
  echo ""
  echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.)"
fi

echo "✓ rawenv installed to $BIN_DIR/rawenv"
