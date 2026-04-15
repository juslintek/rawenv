#!/usr/bin/env bash
set -euo pipefail

REPO="rawenv/rawenv"
INSTALL_DIR="$HOME/.rawenv/bin"

# Detect OS and arch
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) os_target="macos" ;;
  Linux)  os_target="linux" ;;
  *)      echo "Error: unsupported OS: $OS" >&2; exit 1 ;;
esac

case "$ARCH" in
  arm64|aarch64) arch_target="aarch64" ;;
  x86_64|amd64)  arch_target="x86_64" ;;
  *)             echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

TARGET="${arch_target}-${os_target}"
ARCHIVE="rawenv-${TARGET}.tar.gz"

# Get latest version if not specified
VERSION="${RAWENV_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)"
fi

BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Installing rawenv ${VERSION} (${TARGET})..."

# Download archive and checksums
curl -fsSL "${BASE_URL}/${ARCHIVE}" -o "${TMP}/${ARCHIVE}"
curl -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP}/SHA256SUMS"

# Verify checksum
cd "$TMP"
if command -v sha256sum >/dev/null 2>&1; then
  grep "$ARCHIVE" SHA256SUMS | sha256sum -c --quiet
else
  grep "$ARCHIVE" SHA256SUMS | shasum -a 256 -c --quiet
fi

# Install
mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE" -C "$INSTALL_DIR"
chmod +x "${INSTALL_DIR}/rawenv"

# Add to PATH
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
