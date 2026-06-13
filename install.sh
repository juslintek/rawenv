#!/usr/bin/env bash
set -euo pipefail

REPO="juslintek/rawenv"
INSTALL_DIR="$HOME/.rawenv/bin"

# Detect OS and arch
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64|aarch64) ARTIFACT="rawenv-aarch64-macos.tar.gz" ;;
      x86_64|amd64)  ARTIFACT="rawenv-x86_64-macos.tar.gz" ;;
      *) echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$ARCH" in
      aarch64|arm64) ARTIFACT="rawenv-aarch64-linux.tar.gz" ;;
      x86_64|amd64)  ARTIFACT="rawenv-x86_64-linux.tar.gz" ;;
      *) echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*)
    ARTIFACT="rawenv-x86_64-windows.zip"
    ;;
  *) echo "Error: unsupported OS: $OS" >&2; exit 1 ;;
esac

# Get latest version if not specified
VERSION="${RAWENV_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)"
fi

BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing rawenv ${VERSION} (${ARTIFACT})..."

curl -fsSL "${BASE_URL}/${ARTIFACT}" -o "${TMP}/${ARTIFACT}"

# Extract
mkdir -p "$INSTALL_DIR"
case "$ARTIFACT" in
  *.tar.gz)
    tar -xzf "${TMP}/${ARTIFACT}" -C "$TMP"
    mv "${TMP}/rawenv" "$INSTALL_DIR/rawenv" 2>/dev/null || \
      find "$TMP" -name rawenv -type f -exec mv {} "$INSTALL_DIR/rawenv" \;
    ;;
  *.zip)
    unzip -qo "${TMP}/${ARTIFACT}" -d "$TMP"
    mv "${TMP}/rawenv.exe" "$INSTALL_DIR/rawenv.exe" 2>/dev/null || \
      find "$TMP" -name "rawenv.exe" -type f -exec mv {} "$INSTALL_DIR/rawenv.exe" \;
    ;;
esac

chmod +x "$INSTALL_DIR/rawenv" 2>/dev/null || true

echo ""
echo "✓ rawenv installed to $INSTALL_DIR/rawenv"
echo ""
echo "Add to your PATH (add to ~/.zshrc or ~/.bashrc):"
echo "  export PATH=\"\$HOME/.rawenv/bin:\$PATH\""
echo ""
echo "Then verify:"
echo "  rawenv --version"
