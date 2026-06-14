#!/usr/bin/env bash
# quality-guards.sh — static checks for the anti-patterns called out in real PR
# reviews (see ~/.kiro/steering/code-review-lessons.md). Sourced by pre-commit
# (staged files) and pre-push (changed files). Bash 3.2 compatible.
#
#   quality_guards <file> [<file> ...]   # returns non-zero if any violation found

# Print a violation line.
_qg_hit() { printf '  \033[0;31m✗\033[0m %s\n' "$*"; }

quality_guards() {
  local fail=0 f
  for f in "$@"; do
    [ -f "$f" ] || continue
    case "$f" in
      .git/* | */vendor/* | */node_modules/* | *.md) continue ;;
      .githooks/quality-guards.sh) continue ;;
    esac

    # 1. Hardcoded developer paths in code/CI (portability + privacy).
    case "$f" in
      *.swift | *.zig | *.vala | *.cs | *.sh | *.bash | *.py | *.yml | *.yaml | *.toml | Dockerfile* | *.csproj)
        if grep -nE '/Volumes/|/Users/[^/" '"'"']+/|/home/[^/" '"'"']+/' "$f" >/dev/null 2>&1; then
          _qg_hit "$f: hardcoded developer path — use \$ENV, repo-relative, or discovery"
          grep -nE '/Volumes/|/Users/[^/" '"'"']+/|/home/[^/" '"'"']+/' "$f" | head -3 | sed 's/^/        /'
          fail=1
        fi
        ;;
    esac

    # 2. Masking a test/build failure with '|| true'.
    case "$f" in
      *.yml | *.yaml | *.sh | *.bash | Dockerfile*)
        if grep -nE '(pytest|swift test|zig build test|meson test|go test|npm test|cargo test|swift build|zig build)[^|]*\|\|[[:space:]]*true' "$f" >/dev/null 2>&1; then
          _qg_hit "$f: masking a test/build failure with '|| true' — use a visible continue-on-error step instead"
          fail=1
        fi
        ;;
    esac

    # 3. Unpinned third-party GitHub Actions (must be @<40-hex-sha>).
    case "$f" in
      .github/workflows/*.yml | .github/workflows/*.yaml)
        while IFS= read -r line; do
          local owner ref
          owner=$(printf '%s' "$line" | sed -E 's/.*uses:[[:space:]]*//; s#/.*##')
          ref=$(printf '%s' "$line" | sed -E 's/.*@//; s/[[:space:]].*//')
          case "$owner" in actions | github) continue ;; esac
          if ! printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$'; then
            _qg_hit "$f: third-party action not SHA-pinned -> $(printf '%s' "$line" | sed -E 's/^[[:space:]]*//')"
            fail=1
          fi
        done < <(grep -E 'uses:[[:space:]]*[^./[:space:]]+/[^@[:space:]]+@' "$f")
        ;;
    esac

    # 4. Committed hook-skip directives.
    if grep -nE -- '--no-verify|core\.hooksPath=/dev/null|HUSKY=0' "$f" >/dev/null 2>&1; then
      _qg_hit "$f: contains a hook-skip directive — hooks must never be bypassed"
      fail=1
    fi
  done
  return "$fail"
}
