# RULES.md — Engineering, Process & Agent Rules

Consolidated from the Kiro steering rules (`~/.kiro/steering/*`) and `AGENTS.md`.
Every agent and contributor working on this repo follows these. They are distilled
from real PR review feedback (CodeRabbit, Amazon Q, ChatGPT Codex) and hard-won
operational lessons. When a rule and a task conflict, raise it — don't silently
break the rule.

> Project-local environment context (machine paths, credentials) lives in the
> agent-local steering, **not here** — RULES.md is committed and must stay
> secret-free.

---

## 1. Engineering principles

- **SOLID** — one responsibility per type; extend via protocols not modification;
  implementations substitute for their abstraction; small focused protocols;
  depend on abstractions, inject implementations.
- **YAGNI** — no features, abstractions, or code paths not required by the current
  task. No speculative generality.
- **KISS** — prefer simple, readable solutions over clever ones. A 10-line function
  beats a 3-class hierarchy that does the same thing.
- **DRY** — extract shared logic; if you copy-paste, you're doing it wrong (one
  hardcoded path copy-pasted into 21 files cost a cleanup — extract a resolver).

### Code smells / refactor triggers
- Long method > 20 lines · Large class > 200 lines · > 3 params → parameter object
  · > 5 dependencies → split · duplicated logic across 2+ files → extract.

## 2. Ponytail — lazy senior dev (efficient, not careless)

The best code is the code never written. Before writing any, stop at the first rung
that holds: (1) does this need to exist (YAGNI)? (2) does the stdlib do it? (3) a
native platform feature? (4) an already-installed dependency? (5) can it be one
line? (6) only then write the minimum that works.

- No abstractions/dependencies/boilerplate nobody asked for. Deletion over addition,
  boring over clever, fewest files possible.
- Pick the edge-case-correct option when two stdlib approaches are the same size.
- Mark intentional simplifications with a `ponytail:` comment naming the ceiling and
  upgrade path.
- **Not lazy about**: input validation at trust boundaries, error handling that
  prevents data loss, security, accessibility, anything explicitly requested.
- Non-trivial logic leaves ONE runnable check behind (smallest thing that fails if
  the logic breaks — an assert/demo or one small test; no frameworks/fixtures).

## 3. Quality gates & hooks (MANDATORY)

The local git hooks (`.githooks/`, enabled via `bash .githooks/install.sh`) enforce
these on commit and push.

1. **NEVER skip git hooks** — no `--no-verify`, `-n`, `HUSKY=0`,
   `core.hooksPath=/dev/null`, or any bypass on commit/push. A failing hook means the
   work isn't done; fix the cause. The hooks reject committing files containing a
   hook-skip directive.
2. **Never mask failures** — no `|| true`, `|| exit 0`, `set +e`, in-script
   `continue-on-error`, or swallowed non-zero exits around test/build/lint. If a
   check is environment-fragile, make it a *visible* `continue-on-error:` CI step,
   never hide a failure as success.
3. **No hardcoded developer paths** (`/Volumes/...`, `/Users/<name>/...`,
   `/home/<name>/...`) in source/tests/CI. Resolve via env vars (`RAWENV_BINARY`,
   `RAWENV_REPO`, `HOME`), repo-relative paths, or discovery — validating
   existence/executability before use.
4. **Pin ALL CI actions to a 40-char commit SHA** (`uses: owner/action@<sha> # vX`),
   not a mutable tag (`@v4`, `@main`) — including first-party `actions/*`. SAST tools
   enforce a blanket pin policy.

## 4. Code review — hard rules (non-negotiable)

1. **Never skip hooks** (see §3.1).
2. **Never mask failures** (see §3.2).
3. **No hardcoded developer paths** (see §3.3).
4. **No blocking I/O on the UI/main actor** — `waitUntilExit()`, synchronous
   network/file reads, and long loops run off the main thread/actor; hop back to the
   main actor only for state updates.
5. **Pin ALL CI actions to a SHA** (see §3.4).
6. **Validate before trust** — before executing a resolved binary or loading a
   resolved file, verify it exists and is executable/valid; surface a clear error
   otherwise.

## 5. Process rules

7. **Re-check ALL reviewers after EVERY push** — read the *latest* review from
   *every* bot/human (CodeRabbit, Amazon Q, Codex, humans); a push triggers
   re-review and an earlier "clean" doesn't cover a later push.
8. **CI parity / platform guards** — a test runs only where its feature exists
   (`if (comptime os.tag == .windows) return error.SkipZigTest;`); make CI a
   build-check (not test-run) on cross-compile-only targets.
9. **Cross-platform shell** — hooks/scripts target the oldest shell in play (macOS
   ships bash 3.2: no `mapfile`, no associative arrays). Degrade gracefully when a
   tool is absent.
10. **Verify the fix with cited evidence** — reproduce the strict condition locally
    (`swift build -Xswiftc -strict-concurrency=complete`) before pushing.
11. **Confirm the branch before editing** — `git branch --show-current` before a
    batch of edits (a commit landed on `main` by accident when the tree had moved).
12. **Grep-verify bulk edits** — after a find/replace across many files, grep for the
    *old* pattern to confirm zero remain; search for multi-line/wrapped forms a
    single-line replace misses.
13. **Wait for CodeRabbit to self-approve — never clear it yourself.** A PR is NOT
    done while `reviewDecision` is `CHANGES_REQUESTED`. Its state is sticky — a later
    `COMMENTED` re-review does NOT lift it; only an `APPROVED` review from CodeRabbit
    does. Fix everything → reply → resolve threads → re-trigger (`@coderabbitai
    review`) → poll `reviewDecision` until CodeRabbit itself posts `APPROVED`. Never
    dismiss its review, merge over `CHANGES_REQUESTED`, or treat a green check /
    manual resolution as approval.
14. **Verify a push actually landed** — `git ls-remote <remote> <branch>` HEAD ==
    local HEAD. A push can be silently blocked by the pre-push gate (failing/flaky
    test) or a repo ruleset (`non_fast_forward`).
15. **Never over-filter command output that can hide a failure** — keep
    `error|✗|blocked|rejected|failed` lines; never grep only success markers
    (`✓`/`->`), which hides a blocked push or failed gate.
16. **A "hardcoded path" can be a load-bearing default** — before deleting a path
    literal, check whether a feature depends on it (a default scan root/mount).
    Replace a machine-specific *functional default* with a generic equivalent
    (enumerate `/Volumes/*`), don't just remove it — and **exercise the feature**
    after, not just unit tests.
17. **De-flake fixed-sleep races** — a test that sleeps a fixed duration then asserts
    on async state is flaky under load; poll the condition with a timeout instead.
18. **Confirm the branch before committing — every time** (`git branch
    --show-current`).
19. **Never run interactive commands via the shell tool** (see §7).

When a reviewer flags something: verify each finding against current code; fix
still-valid issues with the minimal change; if already mitigated/not applicable, say
so with a brief, specific reason — never silently ignore it.

## 6. Write it right the first time (prevent findings at authoring time)

- **Paths** — never author an absolute machine path; resolve via env + repo-relative
  fallback or a shared helper. Synthetic placeholders (`/home/user`, `/Users/test`)
  are OK as test *inputs*; well-known fixed mounts (macOS VM share `/Volumes/My
  Shared Files/`) are OK; real mounts and your own home are not.
- **Optionals/casts** — no `as!` / `try!` / trailing `!`; guard with a fallback. For
  CoreFoundation/AX types with no Swift `as?`, gate on `CFGetTypeID(x) ==
  T.GetTypeID()` then force-cast, with any `// swiftlint:disable:next` justification
  on a *separate* line above.
- **Concurrency** — no blocking I/O on the main actor; background it, hop back only
  for state.
- **CI actions** — pin every `uses:` to a 40-hex SHA the moment you add it.
- **No masking** — never `… || true`; use a visible `continue-on-error:` step.
- **Format + lint before the first commit** (`swift format`, `zig fmt`,
  `shfmt -i 2 -ci`, swiftlint) — a day-one-clean tree never needs a 60-file format
  diff later.
- **Don't copy-paste machine state** — extract one resolver/helper.

### Tooling gotchas (cost real rounds)
- **SwiftLint disable** is parsed strictly: text after the rule name becomes more
  "rule names". Put justifications on a *separate* comment line above.
- **Don't embed a forbidden literal to test for its absence** (`!hasPrefix("/Volumes/")`
  trips path guards) — prefer the positive assertion (`hasPrefix(home)`).
- **Zig 0.16 env**: `std.posix.getenv` / `std.process.getEnvVarOwned` are gone — use
  `std.c.getenv(name)` + `std.mem.sliceTo(s, 0)`. `std.fs.Dir` moved under
  `std.Io.Dir` (iteration needs an `Io`).
- **Reformatting re-opens lines to the added-line guard** — keep files clean
  continuously so a later format pass is a no-op.
- **A green bot check can reflect an old commit** — re-trigger + re-read every
  reviewer after a push.

## 7. Shell / tool safety — never block the chat

The `shell` tool runs **non-interactively**; any command that opens an interactive
prompt (password, confirmation, pager, REPL, login) hangs forever.

1. **Never run a command that can prompt.** If it could block on input, make it
   non-interactive or hand it to the user.
2. **Redirect stdin from /dev/null** on anything that might prompt: `cmd < /dev/null`.
3. **Wrap slow/hanging commands in a timeout**: `timeout 120 cmd < /dev/null`.
4. **sudo** — never bare `sudo`. Prefer no-sudo paths (`~/.local/bin`); if a password
   is authorized use `echo "$PW" | sudo -S -p '' cmd`; else hand the command to the
   user.
5. **Install scripts / package managers** — pass non-interactive flags (`-y`,
   `--yes`, `DEBIAN_FRONTEND=noninteractive`, `HOMEBREW_NO_AUTO_UPDATE=1`). Unknown
   scripts: read first or hand to the user.
6. **No pagers / editors / REPLs** — `| cat`, `git --no-pager`, `PAGER=cat`; never
   launch `vim`/`nano`/bare `python`/`psql` without `-c`.
7. **Login/auth flows** (`gh auth login`, `coderabbit auth login`, `aws configure`,
   `docker login`) are interactive — hand them to the user.

Prefer a copy-pasteable command for the user over risking a hang.

## 8. Git

- **Always use SSH, never HTTPS** for remotes/clone/push/pull
  (`git@github.com:owner/repo.git`). A global `insteadOf` rewrite enforces this; if a
  remote is HTTPS, convert it. Don't fall back to HTTPS when SSH auth fails — fix the
  key/agent.
- **Branches & PRs** — create branches + PRs for changes; never push to `main` unless
  explicitly told. Use non-interactive git (`GIT_PAGER=cat`). Destructive ops
  (`reset --hard`, `push --force`, `clean -f`, `branch -D`) require explicit consent
  (and may be blocked by repo rulesets — verify before relying on them).
- Confirm the branch (§11/§18) and verify the push landed (§14) every time.

## 9. Local AI code review (pre-commit, no PR)

Prefer a **local** review pass over slow PR reviews. Run before committing
non-trivial changes; the same review rules (§4–§6) apply to the findings.

- **CodeRabbit CLI** (`coderabbit`/`cr`): the shell tool doesn't source `~/.zshrc`,
  so pass `CODERABBIT_API_KEY` explicitly (extract without echoing the value), with a
  timeout + `</dev/null`:
  ```sh
  coderabbit review --plain --type uncommitted   # working tree before a commit
  coderabbit review --plain --base-commit HEAD~1 # what a commit introduced
  ```
  `--agent` emits parseable structured findings. Loop: review → fix still-valid
  findings → re-review until **"No findings"** → commit.
- **Codex CLI** (`codex`, ChatGPT-authed) — a second opinion, agentic/verbose:
  ```sh
  codex review --uncommitted </dev/null
  codex review --commit HEAD </dev/null
  codex review --base main </dev/null
  ```
- **Amazon Q** — its CLI is an interactive `q chat` TUI (no non-interactive local-diff
  review); keep it as a **PR reviewer**, or use `q chat` + `/review` interactively
  (hand to the user — never drive the TUI via the shell tool).

## 10. Testing & verification

- Every public method has a unit test; every screen has an E2E test (Page Object
  pattern); ViewModels tested independently of views; mock data from shared fixtures.
- All interactive elements have accessibility identifiers.
- After any code change: run the build/compile step, then the relevant tests, before
  presenting the result; clean up temp files.
