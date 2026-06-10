#!/usr/bin/env bash
#
# gen-homebrew-formula.sh — render the Homebrew formula for a release.
#
# Substitutes the version and the four platform sha256 checksums into the
# template at packaging/homebrew/rawenv.rb and prints the resolved formula
# to stdout.
#
# Usage:
#   scripts/gen-homebrew-formula.sh <version> <sha256sums-file>
#
# <version>          Release version without the leading "v" (e.g. 1.0.0).
# <sha256sums-file>  A SHA256SUMS file produced by `sha256sum rawenv-*`, with
#                    lines of the form "<hash>  rawenv-darwin-arm64".
set -euo pipefail

VERSION="${1:?usage: gen-homebrew-formula.sh <version> <sha256sums-file>}"
SUMS_FILE="${2:?usage: gen-homebrew-formula.sh <version> <sha256sums-file>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../packaging/homebrew/rawenv.rb"

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: formula template not found at $TEMPLATE" >&2
  exit 1
fi

# Look up the checksum for a given artifact name from the SHA256SUMS file.
sum_for() {
  local artifact="$1"
  local line
  line="$(grep -E "[[:space:]]${artifact}\$" "$SUMS_FILE" || true)"
  if [ -z "$line" ]; then
    echo "Error: no checksum found for ${artifact} in ${SUMS_FILE}" >&2
    exit 1
  fi
  # First whitespace-separated field is the hash.
  echo "$line" | awk '{print $1}'
}

SHA_DARWIN_ARM64="$(sum_for rawenv-darwin-arm64)"
SHA_DARWIN_X64="$(sum_for rawenv-darwin-x64)"
SHA_LINUX_ARM64="$(sum_for rawenv-linux-arm64)"
SHA_LINUX_X64="$(sum_for rawenv-linux-x64)"

sed \
  -e "s|VERSION|${VERSION}|g" \
  -e "s|SHA256_DARWIN_ARM64|${SHA_DARWIN_ARM64}|g" \
  -e "s|SHA256_DARWIN_X64|${SHA_DARWIN_X64}|g" \
  -e "s|SHA256_LINUX_ARM64|${SHA_LINUX_ARM64}|g" \
  -e "s|SHA256_LINUX_X64|${SHA_LINUX_X64}|g" \
  "$TEMPLATE"
