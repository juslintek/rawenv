#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
ARCH="$(uname -m)"
DMG_NAME="rawenv-${VERSION}-${ARCH}"
BUILD_DIR="/tmp/rawenv-dmg-build"
APP_DIR="${BUILD_DIR}/rawenv"

echo "Building rawenv ${VERSION} DMG for ${ARCH}..."

# 1. Build release binary
cd "$(dirname "$0")/.."
zig build -Doptimize=ReleaseSafe -Dgui=true
BINARY="zig-out/bin/rawenv"

if [ ! -f "$BINARY" ]; then
  echo "Error: binary not found at $BINARY"
  exit 1
fi

echo "  Binary: $(ls -lh "$BINARY" | awk '{print $5}')"

# 2. Prepare DMG contents
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR"

cp "$BINARY" "$APP_DIR/rawenv"
chmod +x "$APP_DIR/rawenv"

# Create the install helper script
cat > "$APP_DIR/install.command" << 'INSTALL'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.rawenv/bin"

echo ""
echo "  ⚡ rawenv installer"
echo ""

# Copy binary
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/rawenv" "$INSTALL_DIR/rawenv"
chmod +x "$INSTALL_DIR/rawenv"

# Add to PATH
EXPORT_LINE='export PATH="$HOME/.rawenv/bin:$PATH"'
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
  if [ -f "$rc" ] && ! grep -qF '.rawenv/bin' "$rc"; then
    echo "" >> "$rc"
    echo "# rawenv" >> "$rc"
    echo "$EXPORT_LINE" >> "$rc"
    echo "  Added to PATH in $(basename "$rc")"
  fi
done

echo ""
echo "  ✓ rawenv installed to $INSTALL_DIR/rawenv"
echo "  ✓ Version: $("$INSTALL_DIR/rawenv" --version)"
echo ""
echo "  Restart your terminal, then run:"
echo "    rawenv init"
echo ""
read -p "  Press Enter to close..."
INSTALL
chmod +x "$APP_DIR/install.command"

# Create README
cat > "$APP_DIR/README.txt" << 'README'
rawenv — Raw native dev environments. Zero overhead.

INSTALL:
  Double-click "install.command" to install rawenv to ~/.rawenv/bin/
  and add it to your PATH.

  Or manually:
    cp rawenv/rawenv ~/.rawenv/bin/
    export PATH="$HOME/.rawenv/bin:$PATH"

QUICK START:
  cd your-project
  rawenv init          # detect stack, generate rawenv.toml
  rawenv add node@22   # download + install Node.js
  rawenv up            # activate runtimes
  rawenv shell         # enter environment with correct PATH

MORE: https://github.com/juslintek/rawenv
README

# 3. Create DMG
DMG_PATH="packaging/${DMG_NAME}.dmg"
mkdir -p packaging

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create DMG from folder
hdiutil create \
  -volname "rawenv ${VERSION}" \
  -srcfolder "$BUILD_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# Cleanup
rm -rf "$BUILD_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
echo ""
echo "To test:"
echo "  open $DMG_PATH"
