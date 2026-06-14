#!/usr/bin/env bash
# install.sh — activate the rawenv git hooks and report/install the quality tools.
#
#   bash .githooks/install.sh            # set core.hooksPath + report tool status
#   bash .githooks/install.sh --tools    # also `brew install` any missing tools (macOS)
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

ok() { printf '\033[0;32m✓\033[0m %s\n' "$*"; }
miss() { printf '\033[1;33m✗\033[0m %s\n' "$*"; }
note() { printf '\033[0;36m==>\033[0m %s\n' "$*"; }

# 1. Point git at the tracked hooks dir + make hooks executable.
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push .githooks/post-commit 2>/dev/null || true
note "core.hooksPath = .githooks (active)"

# 2. Report tool availability.
note "Quality toolchain status:"
purpose() {
  case "$1" in
    zig) echo "core build/test + zig fmt" ;;
    swift) echo "macOS GUI build/test" ;;
    swiftlint) echo "Swift strict lint" ;;
    shellcheck) echo "shell lint" ;;
    shfmt) echo "shell format" ;;
    yamllint) echo "YAML lint" ;;
    dotnet) echo "Windows GUI tests (optional on macOS)" ;;
    meson) echo "Linux GUI build (optional on macOS)" ;;
    valac) echo "Linux GUI compile (optional on macOS)" ;;
    *) echo "" ;;
  esac
}
missing_brew=()
for t in zig swift swiftlint shellcheck shfmt yamllint dotnet meson valac; do
  if command -v "$t" >/dev/null 2>&1; then
    ok "$t — $(purpose "$t")"
  else
    miss "$t — $(purpose "$t") (missing)"
    case "$t" in swiftlint | shellcheck | shfmt | yamllint) missing_brew+=("$t") ;; esac
  fi
done
# `swift format` is a subcommand, not its own binary.
if swift format --version >/dev/null 2>&1; then ok "swift format — Swift formatter (toolchain)"; else miss "swift format — install a Swift 6 toolchain"; fi

# 3. Optionally install the brew-available linters.
if [ "${1:-}" = "--tools" ] && [ ${#missing_brew[@]} -gt 0 ]; then
  if command -v brew >/dev/null 2>&1; then
    note "Installing: ${missing_brew[*]}"
    brew install "${missing_brew[@]}"
  else
    miss "Homebrew not found — install it from https://brew.sh then re-run with --tools"
  fi
elif [ ${#missing_brew[@]} -gt 0 ]; then
  note "Install the missing linters with:  brew install ${missing_brew[*]}"
  note "...or re-run:  bash .githooks/install.sh --tools"
fi

note "Hooks installed. pre-commit=autofix, pre-push=build+test+lint gate, post-commit=macOS app install."
