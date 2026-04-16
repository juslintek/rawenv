#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.2.0}"
ARCH="$(uname -m)"
DMG_NAME="rawenv-${VERSION}-${ARCH}"
BUILD_DIR="/tmp/rawenv-dmg-build"

cd "$(dirname "$0")/.."
echo "Building rawenv ${VERSION} DMG for ${ARCH}..."

# 1. Build release binary
zig build -Doptimize=ReleaseSafe -Dgui=true
echo "  Binary: $(ls -lh zig-out/bin/rawenv | awk '{print $5}')"

# 2. Build installer .app
bash packaging/installer/build.sh

# 3. Prepare DMG contents
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy installer app (primary way to install)
cp -R "zig-out/bin/rawenv Installer.app" "$BUILD_DIR/"

# Embed rawenv binary in the installer's Resources
cp zig-out/bin/rawenv "$BUILD_DIR/rawenv Installer.app/Contents/Resources/rawenv"

# Also include standalone binary for manual install
mkdir -p "$BUILD_DIR/rawenv"
cp zig-out/bin/rawenv "$BUILD_DIR/rawenv/rawenv"
chmod +x "$BUILD_DIR/rawenv/rawenv"

cat > "$BUILD_DIR/rawenv/README.txt" << 'README'
Manual install: cp rawenv ~/.rawenv/bin/ && export PATH="$HOME/.rawenv/bin:$PATH"
Or use the "rawenv Installer" app.
README

# 4. Create DMG
DMG_PATH="packaging/${DMG_NAME}.dmg"
mkdir -p packaging
rm -f "$DMG_PATH"

hdiutil create \
  -volname "rawenv ${VERSION}" \
  -srcfolder "$BUILD_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$BUILD_DIR"

echo ""
echo "✓ DMG created: $DMG_PATH"
echo "  Size: $(ls -lh "$DMG_PATH" | awk '{print $5}')"
