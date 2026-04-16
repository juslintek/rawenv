#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../../zig-out/bin"
APP_DIR="${OUT_DIR}/rawenv.app"

echo "Building rawenv GUI..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swiftc -O -parse-as-library -o "$APP_DIR/Contents/MacOS/rawenv-gui" "$SCRIPT_DIR/DashboardApp.swift"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>rawenv</string>
    <key>CFBundleIdentifier</key><string>com.rawenv.gui</string>
    <key>CFBundleVersion</key><string>0.2.0</string>
    <key>CFBundleExecutable</key><string>rawenv-gui</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "✓ Built: $APP_DIR"
ls -lh "$APP_DIR/Contents/MacOS/rawenv-gui"
