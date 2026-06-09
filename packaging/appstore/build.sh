#!/usr/bin/env bash
# Build a Mac App Store .pkg for rawenv: archive -> exportArchive (method app-store).
#
# Requirements (developer-specific, supplied via env — never committed):
#   DEVELOPMENT_TEAM   Apple Developer Team ID (e.g. ABCDE12345)   [required]
# Signing uses automatic provisioning; you must be signed into Xcode with an
# account that has an "Apple Distribution" cert + a Mac App Store provisioning
# profile for bundle id io.rawenv.app.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")/../../gui/macos" && pwd)"
BUILD_DIR="${MACOS_DIR}/build/appstore"
ARCHIVE="${BUILD_DIR}/Rawenv.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"

cd "$MACOS_DIR"
command -v xcodegen >/dev/null && xcodegen generate

rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

echo "==> Archiving (Release)…"
xcodebuild archive \
  -project Rawenv.xcodeproj \
  -scheme Rawenv \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

# ExportOptions generated from env so no team id is committed.
cat > "${BUILD_DIR}/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store</string>
    <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> Exporting App Store package…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

PKG="$(find "$EXPORT_DIR" -name '*.pkg' | head -1)"
echo "✓ App Store package: ${PKG:-<not found>}"
echo
echo "Upload to App Store Connect with either:"
echo "  xcrun altool --upload-app -f \"$PKG\" -t macos --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
echo "  (or drag it into Transporter.app)"
