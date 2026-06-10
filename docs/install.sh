#!/bin/sh
set -e

REPO="juslintek/rawenv"
INSTALL_DIR="${RAWENV_INSTALL_DIR:-$HOME/.rawenv}"
BIN_DIR="$INSTALL_DIR/bin"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux) ARTIFACT="rawenv-linux-${ARCH}" ;;
  darwin) ARTIFACT="rawenv-darwin-${ARCH}" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

echo "Installing rawenv ($ARTIFACT)..."

mkdir -p "$BIN_DIR"

DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ARTIFACT"
curl -fsSL "$DOWNLOAD_URL" -o "$BIN_DIR/rawenv"
chmod +x "$BIN_DIR/rawenv"

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo ""
  echo "Add rawenv to your PATH:"
  echo "  export PATH=\"$BIN_DIR:\$PATH\""
  echo ""
  echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.)"
fi

echo "✓ rawenv installed to $BIN_DIR/rawenv"
