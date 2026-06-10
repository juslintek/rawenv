# QA Findings Log

A living log of every bug and UX gap discovered during E2E test runs and
exploratory testing of rawenv. Each finding gets an ID, is triaged by severity,
and is tracked from discovery through resolution.

> **Process rule:** Every **blocker** and **major** finding MUST be converted
> into a user story (and linked here) **before VERIFY-040** runs. Minor and
> trivial findings may be batched or deferred, but must still be recorded.

---

## Summary

| Metric | Count |
|--------|-------|
| Total findings | 7 |
| 🔴 Open | 7 |
| 🟢 Resolved | 0 |
| ⛔ Blockers (open) | 2 |
| 🟠 Majors (open) | 2 |

**Status:** First exploratory run (EXPLORE-030, qwik-fullstack end-to-end)
logged 7 findings: 2 blockers, 2 majors, 3 minor/trivial. The blockers (QF-001
install path, QF-007 corrupted test file) must be converted to user stories
before VERIFY-040.

---

## Severity Definitions

| Severity | Meaning | Action required |
|----------|---------|-----------------|
| ⛔ Blocker | Core flow broken, data loss, crash, or security hole. Cannot ship. | Convert to user story before VERIFY-040 |
| 🟠 Major | Important feature degraded or broken; notable UX failure with no easy workaround. | Convert to user story before VERIFY-040 |
| 🟡 Minor | Cosmetic or low-impact issue with an easy workaround. | Record; fix opportunistically |
| ⚪ Trivial | Nitpick, typo, polish. | Record; batch later |

## Status Definitions

| Status | Meaning |
|--------|---------|
| `open` | Reproduced and recorded, not yet fixed |
| `in-progress` | Fix underway (story exists / branch open) |
| `resolved` | Fix landed and verified |
| `wontfix` | Acknowledged, intentionally not fixed (include rationale) |
| `duplicate` | Same root cause as another finding (link it) |

---

## Findings

Each finding uses the template below. IDs are sequential: `QF-001`, `QF-002`, …

<!--
### QF-001 — <short title>

- **Date:** YYYY-MM-DD
- **Severity:** ⛔ Blocker | 🟠 Major | 🟡 Minor | ⚪ Trivial
- **Status:** open | in-progress | resolved | wontfix | duplicate
- **Area:** CLI / TUI / GUI / network / deploy / install / docs / …
- **Source:** E2E (`<test name>`) | exploratory | CI | user report
- **Environment:** OS + version, rawenv version/commit

**Steps to reproduce**
1. …
2. …

**Expected**
> What should happen.

**Actual**
> What actually happened (include error output / screenshot path).

**Fix**
> Root cause + the change that resolved it (or "pending"). Link the commit/PR.

**User story:** <link to story / issue, required for blocker & major before VERIFY-040>
-->

> **Exploratory run context (EXPLORE-030):** Real CLI built from
> `worker-w2-0` (`zig build`, Zig 0.16.0, macOS arm64) and run against the live
> project `/Volumes/Projects/qwik-fullstack` (Qwik 2 + bun + MSSQL/Redis via
> docker-compose). Flow exercised: `detect` → `init` → `status` →
> `services ls` → `connections` → `add` → `up`. No crashes occurred in any
> command. Side effects (a generated `rawenv.toml` and two empty store dirs from
> failed downloads) were cleaned up afterward.

### QF-001 — `rawenv add`/`up` can never download a package (execve has no PATH lookup)

- **Date:** 2026-06-10
- **Severity:** ⛔ Blocker
- **Status:** open
- **Area:** CLI / store (install path)
- **Source:** exploratory (EXPLORE-030)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w2-0

**Steps to reproduce**
1. In `/Volumes/Projects/qwik-fullstack`, run `rawenv add redis@7` (or
   `python@3.12`, or `rawenv up` with an uninstalled service).
2. Observe it prints `Downloading ...` then fails almost instantly (~12 ms).

**Expected**
> The artifact is downloaded (the upstream URLs are valid — verified `HTTP 200`
> for both the redis-stack and nodejs.org URLs), verified, and extracted.

**Actual**
> `Download failed: could not download redis@7.4.0. Check your connection and
> try again.` Failure is instant, not a network timeout. Running the *exact*
> command rawenv uses by hand — `curl -fsSL <url> -o <dest>` — succeeds and
> downloads an 18 MB file in ~3 s. So the URL and network are fine; rawenv's own
> invocation is broken.

**Fix**
> Root cause: `runCommand` in `src/core/store.zig` execs with
> `std.c.execve(argv_z[0].?, ...)` where `argv_z[0]` is a bare command name
> (`"curl"`, `"tar"`, `"unzip"`, `"mv"`). `execve(2)` does **not** search
> `PATH` — it requires a pathname — so the child immediately fails with ENOENT
> and `_exit(127)`, which the parent maps to `StoreError.DownloadFailed`. This
> breaks every install (download + extract + binary move). An earlier-built
> binary populated `~/.rawenv/store/node-22.15.0` (marker dated 02:04), so this
> is a **regression** in the current worktree's store path. Fix: use
> `std.c.execvp` (PATH-searching) or resolve the absolute path before
> `execve`. Secondary: the user-facing message wrongly blames the network —
> distinguish "command not found / internal exec failure" from a real
> connection error. Pending.

**User story:** _required — convert before VERIFY-040 (install path is fully broken)_

---

### QF-002 — MSSQL (azure-sql-edge) service not detected from docker-compose.yml

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector
- **Source:** exploratory (EXPLORE-030)
- **Environment:** macOS arm64, rawenv built from worker-w2-0

**Steps to reproduce**
1. `rawenv detect --json` in qwik-fullstack (compose declares `mssql` using
   `image: mcr.microsoft.com/azure-sql-edge:latest` and `redis:7-alpine`).

**Expected**
> Detected services include both `mssql` and `redis` — the actual project stack.

**Actual**
> Only `{"name":"redis","version":"7",...}` is returned. The `mssql` service is
> silently dropped, so the AC "Detection shows correct stack from package.json +
> docker-compose.yml" is not met.

**Fix**
> Root cause: `parseDockerComposeServices` in `src/core/detector.zig` only
> matches image prefixes `postgres`, `redis`, `mysql`, `mariadb`, `mongo`. It
> does not recognize `mcr.microsoft.com/azure-sql-edge` / `mssql` /
> `sql-server`. Compounding this, the resolver (`src/core/resolver.zig`) has no
> `mssql` package at all, so even a correct detection couldn't be installed yet.
> Add an mssql image matcher and a resolver entry (or emit an actionable
> "detected but unsupported runtime" note). Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-003 — Auto-detected node version (`20`) is not installable (resolver only knows `22`)

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector ↔ resolver mismatch
- **Source:** exploratory (EXPLORE-030)
- **Environment:** macOS arm64, rawenv built from worker-w2-0

**Steps to reproduce**
1. `rawenv init` in qwik-fullstack (its `package.json` has
   `engines.node: ">=20.19.0 || >=22.12.0"`).
2. Generated `rawenv.toml` contains `node = "20"`.
3. Run `rawenv add node@20`.

**Expected**
> A config written by `rawenv init` should be installable by `rawenv add` /
> `rawenv up` — the detect→init→add pipeline must be internally consistent.

**Actual**
> `Unknown version '20' for package 'node'.` The detector's `matchMajor` picks
> the first major in the constraint (`20`), but `resolveNode` only accepts `22`
> / `22.15.0`. So `init` produces a `rawenv.toml` that the tool itself cannot
> act on. (`rawenv up` then reports `node@20 — not installed, skipping`.)

**Fix**
> Reconcile detector output with resolver coverage: either the detector should
> snap to a resolver-supported version (and prefer the highest satisfiable
> major, here 22), or the resolver should support node 20 LTS. The error text
> ("Try a supported version") is reasonable but should ideally list the
> supported versions. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-004 — `bun` package manager ignored; project reported as plain node

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector
- **Source:** exploratory (EXPLORE-030)

**Steps to reproduce**
1. `rawenv detect` in qwik-fullstack (`package.json` has
   `"packageManager": "bun@1.3.10"` and most scripts run via `bun`).

**Expected**
> Detection acknowledges the `bun` toolchain (as a runtime or at least a note),
> since the project's `dev`/`start`/`test` scripts invoke `bun`.

**Actual**
> Only `node 20` is reported. The `packageManager` field is not parsed. Works as
> a node project but loses the bun signal; acceptable workaround is manual edit.

**Fix**
> Parse `packageManager` (and lockfiles like `bun.lock`) in
> `src/core/detector.zig` to detect bun/pnpm/yarn. Pending.

**User story:** n/a (minor)

---

### QF-005 — `rawenv up` "starts" a service whose binary isn't installed (30 s wait, false "started")

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / service manager
- **Source:** exploratory (EXPLORE-030)

**Steps to reproduce**
1. With redis listed in config but not installed, run `rawenv up`.

**Expected**
> Consistent with node, which prints `node@20 — not installed, skipping`, redis
> should also be skipped (or fail fast) when its binary is absent.

**Actual**
> Output: `▶ redis@7.4.0 started` → `✗ redis (port 6381) failed: not ready
> after 30s (tcp probe)` → `■ redis stopped`. It claims "started", blocks for
> 30 s on a TCP probe, then reports failure — even though the binary was never
> installed. Inconsistent handling between runtimes and services. (Exit code is
> still 0, no crash.)

**Fix**
> Gate service start on an "installed" check (same guard used for runtimes) and
> avoid printing "started" before the readiness probe confirms it. Pending.

**User story:** n/a (minor)

---

### QF-006 — Inconsistent service status across `status`, `services ls`, and `detect`

- **Date:** 2026-06-10
- **Severity:** ⚪ Trivial
- **Status:** open
- **Area:** CLI / reporting consistency
- **Source:** exploratory (EXPLORE-030)

**Steps to reproduce**
1. Run `rawenv detect --json`, `rawenv status --json`, and `rawenv services ls`
   back to back in qwik-fullstack.

**Expected**
> The same service/runtime is reported consistently across commands.

**Actual**
> - `services ls` shows `node ... installed`, while `status --json` shows node
>   `"installed": false`.
> - redis version differs: `detect` → `7`, `status`/`up` → `7.4.0`.
> - redis port differs: `detect` → `6379` (compose default), `status`/`up` →
>   `6381` (likely conflict-avoidance remap — fine, but undocumented and
>   inconsistent with what `detect` advertises).

**Fix**
> Centralize the install-state check and version/port resolution so all three
> commands share one source of truth. If port remapping is intentional, surface
> it explicitly. Pending.

**User story:** n/a (trivial)

---

### QF-007 — `tests/service_test.zig` is corrupted with ANSI escape codes; `zig build test` fails to compile

- **Date:** 2026-06-10
- **Severity:** ⛔ Blocker
- **Status:** open
- **Area:** tests / CI
- **Source:** exploratory (EXPLORE-030 quality-check step)
- **Environment:** macOS arm64, Zig 0.16.0, worker-w2-0

**Steps to reproduce**
1. `zig build test` from the worktree root.

**Expected**
> Test suite compiles and runs.

**Actual**
> Compile fails: `tests/service_test.zig:1:1: error: expected type expression,
> found 'invalid token'`. `zig build` (the binary) still succeeds; only the test
> target is broken. Overall: `166/171 tests passed (5 skipped)`, with this one
> file failing to compile. Note: this is pre-existing in the worktree and is
> **not** caused by EXPLORE-030 (which only edits this markdown file).

**Fix**
> Root cause: the file contains raw ANSI terminal escape sequences (e.g.
> `\e[38;5;141m`, `\e[3m`, `\e[0m`) — it looks like colorized compiler/`bat`
> output was saved over the source. Concretely: line 1 carries a literal `> `
> error-pointer prefix (`> const std = @import("std");`), and six `_ = <expr>;`
> discard statements lost their leading `_` where an italic escape replaced it
> (lines ~24, 165, 186, 341, 354, 357, e.g. `  = &cfg;` and
> `  = std.c.close(l.fd);`). Restore by stripping ANSI codes
> (`s/\e\[[0-9;]*m//g`), removing the leading `> ` on line 1, and re-adding the
> `_ ` to the six discard lines, then confirm with `zig build test`. Left to a
> dedicated fix story to avoid colliding with any worker that owns this file.
> Pending.

**User story:** _required — convert before VERIFY-040 (test suite cannot compile)_

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-10 | Log created and initialized (QA-050). |
| 2026-06-10 | EXPLORE-030: first exploratory run (qwik-fullstack end-to-end). Logged QF-001 (blocker), QF-002/QF-003 (majors), QF-004/QF-005 (minor), QF-006 (trivial). |
| 2026-06-10 | EXPLORE-030 quality check: logged QF-007 (blocker) — `tests/service_test.zig` corrupted with ANSI codes, `zig build test` fails to compile. |
