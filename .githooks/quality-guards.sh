#!/usr/bin/env bash
# quality-guards.sh — static checks for the anti-patterns called out in real PR
# reviews (see ~/.kiro/steering/code-review-lessons.md). Sourced by pre-commit
# (staged files) and pre-push (changed files). Bash 3.2 compatible.
#
# Scans ONLY the lines a change ADDS (the staged/pushed diff), never whole files,
# so a commit is judged on what it introduces — pre-existing matches in a file you
# touch for an unrelated reason are not retroactively blocked (PR #3 review).
#
#   QG_DIFF="git diff --cached -U0 --"      quality_guards <file> ...   # pre-commit
#   QG_DIFF="git diff -U0 <base>...HEAD --"  quality_guards <file> ...   # pre-push

# Print a violation line.
_qg_hit() { printf '  \033[0;31m✗\033[0m %s\n' "$*"; }

# Emit the content of lines ADDED to <file> in the configured diff (drops the
# '+++' header and the leading '+'). Empty when nothing was added.
_qg_added() {
  # shellcheck disable=SC2086 # QG_DIFF is a multi-word command, splitting intended.
  ${QG_DIFF:-git diff --cached -U0 --} "$1" 2>/dev/null | sed -n '/^+++/d; s/^+//p'
}

quality_guards() {
  local fail=0 f added hits uses_lines line norm owner ref
  for f in "$@"; do
    case "$f" in
      .git/* | vendor/* | */vendor/* | node_modules/* | */node_modules/* | *.md) continue ;;
      .githooks/quality-guards.sh | .githooks/quality-guards.test.sh) continue ;; # self-skip: hold the patterns/fixtures below
    esac
    added=$(_qg_added "$f")
    [ -n "$added" ] || continue

    # 1. Hardcoded developer paths in code/CI (portability + privacy).
    case "$f" in
      *.swift | *.zig | *.vala | *.cs | *.sh | *.bash | *.py | *.yml | *.yaml | *.toml | *.csproj | Dockerfile* | */Dockerfile*)
        hits=$(printf '%s\n' "$added" | grep -nE '/Volumes/|/Users/[^/" '"'"']+/|/home/[^/" '"'"']+/') || hits=
        if [ -n "$hits" ]; then
          _qg_hit "$f: hardcoded developer path in added lines — use \$ENV, repo-relative, or discovery"
          printf '%s\n' "$hits" | head -3 | sed 's/^/        + /'
          fail=1
        fi
        ;;
    esac

    # 2. Masking a test/build failure with '|| true'.
    case "$f" in
      *.yml | *.yaml | *.sh | *.bash | Dockerfile* | */Dockerfile*)
        if printf '%s\n' "$added" | grep -qE '(pytest|swift test|zig build test|meson test|go test|npm test|cargo test|swift build|zig build)[^|]*\|\|[[:space:]]*true'; then
          _qg_hit "$f: masking a test/build failure with '|| true' — use a visible continue-on-error step instead"
          fail=1
        fi
        ;;
    esac

    # 3. Unpinned GitHub Actions — every action must be @<40-hex-sha> (blanket
    #    SAST policy). Quotes are stripped; docker:// and local ./ refs skipped.
    case "$f" in
      .github/workflows/*.yml | .github/workflows/*.yaml)
        uses_lines=$(printf '%s\n' "$added" | grep -E "uses:[[:space:]]*[\"']?[^[:space:]./][^[:space:]]*/[^@[:space:]]+@") || uses_lines=
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          norm=$(printf '%s' "$line" | sed "s/[\"']//g")
          case "$norm" in *docker://*) continue ;; esac
          owner=$(printf '%s' "$norm" | sed -E 's/.*uses:[[:space:]]*//; s#/.*##')
          ref=$(printf '%s' "$norm" | sed -E 's/.*@//; s/[[:space:]].*//')
          [ -n "$owner" ] || continue
          if ! printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then
            _qg_hit "$f: action not SHA-pinned -> $(printf '%s' "$line" | sed -E 's/^[[:space:]]*//')"
            fail=1
          fi
        done <<EOF
$uses_lines
EOF
        ;;
    esac

    # 4. Committed hook-skip directives.
    if printf '%s\n' "$added" | grep -qE -- '--no-verify|core\.hooksPath=/dev/null|HUSKY=0'; then
      _qg_hit "$f: contains a hook-skip directive — hooks must never be bypassed"
      fail=1
    fi
  done
  return "$fail"
}
