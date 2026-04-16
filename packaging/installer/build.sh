#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../../zig-out/bin"
APP_NAME="rawenv Installer.app"
APP_DIR="${OUT_DIR}/${APP_NAME}"

echo "Building rawenv installer..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile Swift
swiftc \
    -O \
    -parse-as-library \
    -o "$APP_DIR/Contents/MacOS/rawenv-installer" \
    "$SCRIPT_DIR/InstallerApp.swift"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>rawenv Installer</string>
    <key>CFBundleDisplayName</key><string>rawenv Installer</string>
    <key>CFBundleIdentifier</key><string>com.rawenv.installer</string>
    <key>CFBundleVersion</key><string>0.2.0</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleExecutable</key><string>rawenv-installer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

# Copy rawenv binary into Resources (if available)
if [ -f "$OUT_DIR/rawenv" ]; then
    cp "$OUT_DIR/rawenv" "$APP_DIR/Contents/Resources/rawenv"
fi

echo "✓ Built: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/rawenv-installer"
