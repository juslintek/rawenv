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
      arm64|aarch64) ARTIFACT="rawenv-darwin-arm64" ;;
      x86_64|amd64)  ARTIFACT="rawenv-darwin-x64" ;;
      *) echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$ARCH" in
      aarch64|arm64) ARTIFACT="rawenv-linux-arm64" ;;
      x86_64|amd64)  ARTIFACT="rawenv-linux-x64" ;;
      *) echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*)
    ARTIFACT="rawenv-windows-x64.exe"
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

curl -fsSL "${BASE_URL}/${ARTIFACT}" -o "${TMP}/rawenv"

# Install
mkdir -p "$INSTALL_DIR"
cp "${TMP}/rawenv" "${INSTALL_DIR}/rawenv"
chmod +x "${INSTALL_DIR}/rawenv"

# Add to PATH hint
EXPORT_LINE='export PATH="$HOME/.rawenv/bin:$PATH"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
  if [ -f "$rc" ] && ! grep -qF '.rawenv/bin' "$rc"; then
    echo "$EXPORT_LINE" >> "$rc"
  fi
done

echo ""
echo "✓ rawenv ${VERSION} installed to ${INSTALL_DIR}/rawenv"
echo ""
echo "Restart your shell or run:"
echo "  export PATH=\"\$HOME/.rawenv/bin:\$PATH\""
