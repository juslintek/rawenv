#!/usr/bin/env bash
# Self-check for quality-guards.sh. Feeds synthetic `git diff -U0` fixtures via
# QG_DIFF="cat" (so _qg_added reads them straight through) and asserts that the
# guard judges ONLY added lines and handles the PR #3 review edge cases.
# Run: bash .githooks/quality-guards.test.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/quality-guards.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Relative paths so anchored case-globs (.github/workflows/*, vendor/*) match.
cd "$tmp" || exit 1
pass=0
fail=0
# assert <expect 0|1> <label> <relative-file>
assert() {
  local want="$1" label="$2" file="$3"
  QG_DIFF="cat" quality_guards "$file" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1))
    printf '  ✗ %s (want exit %s, got %s)\n' "$label" "$want" "$got"
  fi
}
mk() {
  mkdir -p "$(dirname "$1")"
  printf '%b' "$2" >"$1"
}

# Adds a hardcoded path -> flagged.
mk add.swift '+++ b/x\n+let p = "/Volumes/Projects/rawenv/bin"\n'
assert 1 "added hardcoded path is flagged" add.swift

# Pre-existing path is context ('  ' / no '+') while the ADDED line is clean -> not flagged.
mk svc.zig '+++ b/svc.zig\n@@\n let path = "/home/user/.rawenv";\n+const y = 2;\n'
assert 0 "pre-existing path is not retroactively flagged" svc.zig

# Nested Dockerfile path added -> flagged (root-only glob missed this before).
mk gui/linux/Dockerfile.test '+++ b/d\n+COPY /home/user/app /app\n'
assert 1 "nested Dockerfile path is flagged" gui/linux/Dockerfile.test

# Quoted, SHA-pinned action -> NOT flagged.
mk .github/workflows/pinned.yml '+++ b/w\n+      - uses: "owner/repo@abcdef1234567890abcdef1234567890abcdef12"\n'
assert 0 "quoted SHA-pinned action is not flagged" .github/workflows/pinned.yml

# Unpinned action (mutable tag) added -> flagged.
mk .github/workflows/unpinned.yml '+++ b/w\n+      - uses: actions/checkout@v4\n'
assert 1 "unpinned action is flagged" .github/workflows/unpinned.yml

# Pinned action with an inline comment containing '@' -> NOT flagged (comment stripped).
mk .github/workflows/cmt.yml '+++ b/w\n+      - uses: owner/repo@abcdef1234567890abcdef1234567890abcdef12 # pin @ v4\n'
assert 0 "inline comment with @ does not override the ref" .github/workflows/cmt.yml

# docker:// ref -> skipped (not a GitHub action).
mk .github/workflows/docker.yml '+++ b/w\n+      - uses: docker://alpine:3.20\n'
assert 0 "docker:// ref is skipped" .github/workflows/docker.yml

# Root-level vendor file -> skipped entirely.
mk vendor/lib.go '+++ b/v\n+x := "/Users/bob/x"\n'
assert 0 "root vendor/ is skipped" vendor/lib.go

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
