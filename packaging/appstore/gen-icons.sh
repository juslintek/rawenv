#!/usr/bin/env bash
# Regenerate the macOS AppIcon set from a single high-res source.
# The 1024 "marketing" icon is flattened (no alpha) as required by the App Store.
set -euo pipefail

SRC="${1:-$(cd "$(dirname "$0")/../../gui/macos/Sources/RawenvApp/Assets.xcassets/AppIcon.appiconset" && pwd)/icon_1024.png}"
OUT="$(cd "$(dirname "$0")/../../gui/macos/Sources/RawenvApp/Assets.xcassets/AppIcon.appiconset" && pwd)"

# Keep a pristine source copy the first time we run.
[ -f "$OUT/icon_source.png" ] || cp "$SRC" "$OUT/icon_source.png"
SRC="$OUT/icon_source.png"

for sz in 16 32 64 128 256 512; do
  magick "$SRC" -resize ${sz}x${sz} "$OUT/icon_${sz}.png"
done
# 1024 marketing icon: no alpha (flatten onto white).
magick "$SRC" -resize 1024x1024 -background white -alpha remove -alpha off "$OUT/icon_1024.png"

echo "Generated icons in $OUT"
