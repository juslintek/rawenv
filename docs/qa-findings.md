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
| Total findings | 21 |
| 🔴 Open | 21 |
| 🟢 Resolved | 0 |
| ⛔ Blockers (open) | 2 |
| 🟠 Majors (open) | 10 |

**Status:** Five exploratory runs logged (full 5-project run complete, **zero
crashes**). EXPLORE-034 (gratis, a real 40+-plugin WordPress suite) logged 4 more
(QF-018 major: php defaults to 8.4 ignoring the Dockerfile's php8.3; QF-019
major: mariadb detected but unresolvable; QF-020/QF-021 minor) and reproduced
QF-001/QF-005/QF-006/QF-012/QF-015 against a fifth project. A consolidated
cross-project writeup lives in [`docs/exploratory-report.md`](exploratory-report.md).
EXPLORE-030 (qwik-fullstack) logged 7
findings (2 blockers, 2 majors, 3 minor/trivial). EXPLORE-031 (rentflowiq,
greenfield Bun/SolidStart project) logged 5 more (QF-008…QF-012: 3 majors, 2
minor) and reproduced QF-001/QF-004/QF-005/QF-006 against a second project.
EXPLORE-032 (rahcolours-b2b2c, a real Laravel 11 / PHP 8.3 + Node/Vite app with
a Laravel Sail `docker-compose.yml`) logged 3 more (QF-013/QF-014 majors,
QF-015 minor) and reproduced the QF-003/QF-006 patterns against a third project.
EXPLORE-033 (zelkai-trends, a real Node 22 + Python `uv`/`pyproject.toml`
monorepo) logged 2 more (QF-016 major, QF-017 minor) and reproduced QF-001
against a fourth project — this time for a `python` runtime. The blockers
(QF-001 install path, QF-007 corrupted test file) plus all majors must be
converted to user stories before VERIFY-040.

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

> **Exploratory run context (EXPLORE-031):** Same real CLI rebuilt from this
> worktree (`zig build`, Zig 0.16.0, macOS arm64) and run against the live
> project `/Volumes/Projects/rentflowiq`. Unlike qwik-fullstack, rentflowiq is a
> **greenfield / planning-stage** project: it has docs, research, and a
> hand-written `rawenv.toml` (declaring `bun`, `node`, `postgresql`, `redis`,
> and an `app` service), but **no manifest or source files yet** (no
> `package.json`, `docker-compose.yml`, lockfiles, or code). Intended stack per
> `AGENTS.md`: Bun + SolidStart + PostgreSQL + Redis + MeiliSearch. Flow
> exercised: `detect` → `status` → `services ls` → `connections` → `init` →
> `add` (bun/postgresql/postgres/redis/meilisearch/app) → `up`. Detection of the
> intended stack was also simulated in a temp dir with a representative
> `package.json` + `docker-compose.yml`. No crashes occurred. All side effects
> (failed-download store dirs `postgresql-16.9.0`/`redis-7.4.0`, and the
> `~/.rawenv/certs/rentflowiq` + `~/.rawenv/proxy/rentflowiq.Caddyfile` written
> by `up`) were cleaned up; the project's `rawenv.toml` was left byte-identical.
>
> Reproduced from EXPLORE-030: **QF-001** (`add`/`up` download fails instantly,
> ~24–32 ms, for postgresql & redis — the `execve` PATH bug), **QF-004** (bun
> package manager ignored), **QF-005** (false "started" + 30 s probe per
> uninstalled service), **QF-006** (status vs `services ls` inconsistency:
> bun shows `not installed` in `status` but `installed` in `services ls`;
> versions `16.9.0`/`7.4.0` vs `16`/`7`).

### QF-008 — `app` (the project's own service) is treated as an installable package

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / service manager + status reporting
- **Source:** exploratory (EXPLORE-031)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w3-0

**Steps to reproduce**
1. rentflowiq's `rawenv.toml` declares `[services.app]` with
   `depends_on = ["postgresql", "redis"]` (the project's own application, not a
   downloadable runtime).
2. Run `rawenv status`, then `rawenv add app@latest`, then `rawenv up`.

**Expected**
> A logical/first-party `app` service (one with `depends_on`, no upstream
> artifact) should be recognized as user-managed: not advertised as installable,
> not given a download warning, and either started via a user-provided command
> or clearly marked "managed by you".

**Actual**
> - `status` lists `app  latest  1024  stopped` and warns
>   `⚠ app: binary not installed — run rawenv add app@latest`.
> - `rawenv add app@latest` → `Unknown package: app. Available: node, postgres,
>   redis, python, php, meilisearch` (exit 1).
> - `rawenv up` → `app@latest — not installed, skipping`.
> So `status` tells the user to run a command that `add` then rejects. The port
> defaults to `1024` (a placeholder). `app` has no upstream artifact and should
> never be routed through the package resolver.

**Fix**
> Distinguish first-party/logical services (those with `depends_on` and/or no
> resolver entry) from installable runtimes. Suppress the "binary not installed"
> warning and the `add` suggestion for them; optionally support a `command`/
> `run` field so `up` can launch the app. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-009 — `bun` runtime is unsupported by the resolver, yet `status` recommends `rawenv add bun@1`

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / resolver (+ status guidance)
- **Source:** exploratory (EXPLORE-031)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w3-0

**Steps to reproduce**
1. rentflowiq declares `[runtimes] bun = "1"` (bun is the project's **primary**
   runtime per `AGENTS.md`).
2. `rawenv status` prints `⚠ bun: binary not installed — run rawenv add bun@1`.
3. Run `rawenv add bun@1`.

**Expected**
> rawenv can install bun (it is a first-class JS runtime and this project's core
> toolchain), or — at minimum — `status` does not recommend a command the tool
> cannot fulfill.

**Actual**
> `rawenv add bun@1` → `Unknown package: bun. Available: node, postgres, redis,
> python, php, meilisearch` (exit 1). Root cause: `available_packages` in
> `src/core/resolver.zig` has no `bun` entry (and `resolve` has no `bun`
> branch). So rawenv **cannot set up rentflowiq's primary runtime at all**, and
> the `status` warning text is misleading. (Note: `src/core/service.zig` already
> lists `bun` as an HTTP-style service type at line ~144, so the gap is purely
> in the resolver/installer.)

**Fix**
> Add a `bun` resolver entry (darwin/linux release assets from
> `github.com/oven-sh/bun`) and a `resolveBun`/dispatch branch; include `bun` in
> `available_packages`. Until then, the detector/`status` should not emit an
> `add bun@…` suggestion for an unsupported runtime. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-010 — MeiliSearch not detected from `docker-compose.yml` (`getmeili/meilisearch` image)

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector (two divergent compose parsers)
- **Source:** exploratory (EXPLORE-031, simulated stack)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w3-0

**Steps to reproduce**
1. A compose file with `image: getmeili/meilisearch:v1.10` (rentflowiq's
   intended search service).
2. Run `rawenv detect`.

**Expected**
> Detected services include `meilisearch` (it *is* an installable package —
> `available_packages` lists it).

**Actual**
> Only `postgresql` and `redis` are detected; `meilisearch` is dropped. Root
> cause: `parseDockerComposeServices` in `src/core/detector.zig` only matches
> image prefixes `postgres`/`redis`/`mysql`/`mariadb`/`mongo`. It has no
> meilisearch matcher, and the `getmeili/meilisearch` image doesn't start with
> `meilisearch` anyway. Notably a **second** compose parser,
> `src/core/compose.zig`, *does* have a `meilisearch` matcher (line ~72) — so
> the two parsers diverge and the one used by `detect` is the weaker one.

**Fix**
> Add a meilisearch matcher to `detector.zig` (match both `meilisearch` and the
> official `getmeili/meilisearch` image), or unify `detect` onto the richer
> `compose.zig` parser so there is a single source of truth. Pending.

**User story:** n/a (minor)

---

### QF-011 — Greenfield project: `detect` returns empty (expected) but offers no guidance; `bun` packageManager ignored

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector + UX
- **Source:** exploratory (EXPLORE-031)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w3-0

**Steps to reproduce**
1. In `/Volumes/Projects/rentflowiq` (docs + a hand-written `rawenv.toml`, but
   no `package.json`/compose/source), run `rawenv detect`.
2. Separately, in a temp dir with a representative `package.json`
   (`"packageManager": "bun@1.1.38"`), run `rawenv detect`.

**Expected**
> (a) For a planning-stage repo, `detect` reasonably finds nothing — but could
> note that a `rawenv.toml` already exists and is being used. (b) When a real
> `package.json` carries `packageManager: bun@…`, detection should surface bun.

**Actual**
> (a) `rawenv detect` → `No runtimes or services detected.` (correct, since
> there are no manifests) with no hint that a usable config is already present.
> (b) With the simulated manifest, detection reports only `node 22` — the
> `packageManager` field is not parsed (reproduces QF-004), so bun (the primary
> runtime) is invisible to `detect`/`init`. This is benign on its own but, with
> QF-009, means rawenv neither detects nor installs rentflowiq's core runtime.

**Fix**
> Parse `packageManager` and bun lockfiles (`bun.lock`, `bun.lockb`) in
> `src/core/detector.zig`; consider a `detect` note when a valid `rawenv.toml`
> already exists. Pending. (Depends on QF-009 for bun to be actionable.)

**User story:** n/a (minor; rolls up with QF-004/QF-009)

---

### QF-012 — `rawenv up` exits 0 even when every service fails to start (and blocks 30 s per uninstalled service)

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / service manager (exit codes + readiness)
- **Source:** exploratory (EXPLORE-031)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w3-0

**Steps to reproduce**
1. With no service binaries installed (postgresql, redis), run `rawenv up` and
   check `echo $?`.

**Expected**
> When `up` fails to bring up the requested services, it should return a
> non-zero exit code so CI / `git push → deploy` automation (which the README
> and STARTER-PLAN both rely on) can detect failure. Uninstalled services should
> be skipped fast, not probed for 30 s.

**Actual**
> `up` printed `▶ postgresql@16.9.0 started` then `✗ postgresql (port 5432)
> failed: not ready after 30s (tcp probe)` → `■ postgresql stopped`, then the
> same for redis — **60.9 s total** wall time for two never-installed services
> (extends QF-005: false "started" + 30 s probe, now compounding linearly per
> service). Despite both services failing, the overall command **exited 0**.
> (It still proceeded to write a TLS cert + Caddyfile, which is reasonable, and
> correctly warned that DNS setup needs sudo.)

**Fix**
> (1) Gate the readiness probe on an "installed" check so uninstalled services
> are skipped immediately (shared with QF-005). (2) Track per-service start
> results and return non-zero from `up` if any required service failed. Pending.

**User story:** _required — convert before VERIFY-040_

---

> **Exploratory run context (EXPLORE-032):** Same real CLI rebuilt from this
> worktree (`zig build`, Zig 0.16.0, macOS arm64, binary at
> `zig-out/bin/rawenv`) and run against the live project
> `/Volumes/Projects/rahcolours-b2b2c` — a **real, mature Laravel 11 application**
> (PHP `^8.3` via `composer.json`; Filament, Horizon, Cashier, Jetstream,
> Inertia/Vue + Vite via `package.json`; `bun.lock` present). Its
> `docker-compose.yml` is a standard **Laravel Sail** file declaring
> `mysql:8.0.39`, `redis:alpine`, `axllent/mailpit`, a `node:23-alpine` vite
> container, and a `zenika/alpine-chrome` service; the app container
> `depends_on` mysql/redis/mailpit. Flow exercised: `detect` (+`--json`) →
> `init` → `status` (+`--json`) → `services ls` → `connections` → `add php@8.3`
> → `up`. No crashes occurred in any command. Side effects (the generated
> `rawenv.toml`) were cleaned up afterward; the project was left as found.
>
> The store already contained genuine, fully-installed runtimes
> (`node-22.15.0`, `php-8.3.21`, `php-8.4.0` — all carrying the
> `.rawenv-installed` marker), which made the version-handling gaps below
> reproducible against *real* installed binaries rather than failed downloads.
>
> Reproduced from earlier runs: the **QF-003 pattern** (detect→init writes a
> version the resolver/`add` cannot install — here for **php**, the project's
> primary runtime) and **QF-006** (install-state disagreement between `status`,
> `services ls`, and `up`).

### QF-013 — Quoted `image:` values in `docker-compose.yml` (Laravel Sail style) detect zero services

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector (compose parsing)
- **Source:** exploratory (EXPLORE-032)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w4-1

**Steps to reproduce**
1. In `/Volumes/Projects/rahcolours-b2b2c`, run `rawenv detect --json`. Its
   `docker-compose.yml` (Laravel Sail) declares `image: 'mysql:8.0.39'` and
   `image: 'redis:alpine'` (single-quoted, as Sail and many compose files
   write them).
2. Compare with an identical compose using **unquoted** images
   (`image: mysql:8.0.39` / `image: redis:alpine`).

**Expected**
> Detected services include `mysql` and `redis` regardless of whether the image
> value is quoted.

**Actual**
> `{"runtimes":[{"node":"22"},{"php":"8.3"}],"services":[]}` — **no services at
> all** for a project that clearly runs MySQL + Redis. Controlled test confirms
> the quoting is the cause: unquoted images return
> `mysql` + `redis`; quoted images return `[]`.

**Fix**
> Root cause: `parseDockerComposeServices` in `src/core/detector.zig` does
> `const image = std.mem.trim(u8, trimmed["image:".len..], &whitespace);` and
> then `std.mem.startsWith(u8, image, "mysql")` (etc.). When the value is
> `'mysql:8.0.39'` the leading `'` means it starts with `'`, not `mysql`, so
> every prefix match fails. Strip surrounding single/double quotes from `image`
> before matching (and ideally before `matchMajor` on the `:tag`). This affects
> **every Laravel Sail project** (one of the most common PHP dev stacks) and any
> compose file that quotes image strings. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-014 — PHP (the project's primary runtime) is detected as `8.3` but the resolver only supports `8.4`, so it can never be installed

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector ↔ resolver mismatch (install path)
- **Source:** exploratory (EXPLORE-032)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w4-1

**Steps to reproduce**
1. In rahcolours-b2b2c (`composer.json` requires `php: ^8.3`), run `rawenv init`.
   The generated `rawenv.toml` contains `php = "8.3"`.
2. `rawenv status` prints `⚠ php: binary not installed — run rawenv add php@8.3`.
3. Run `rawenv add php@8.3`.

**Expected**
> A `php` version written by `rawenv init` (and recommended verbatim by
> `status`) must be installable by `rawenv add`. PHP 8.3 is a current,
> widely-deployed LTS and the primary runtime of this app.

**Actual**
> `rawenv add php@8.3` → `Unknown version '8.3' for package 'php'. Try a
> supported version (e.g. rawenv add php@<version>).` (exit 1). Root cause:
> `resolvePhp` in `src/core/resolver.zig` accepts **only** `"8.4"` / `"8.4.11"`
> and returns `UnknownVersion` for everything else; `fullVersion` likewise maps
> only `php "8.4" → 8.4.11`. So the detect→init→add pipeline is internally
> inconsistent for php, and rawenv **cannot set up this project's core
> runtime** (it would force an unrequested major upgrade to 8.4). This is the
> same class as QF-003 (node@20) but more severe because php is the primary
> runtime here. `rawenv up` then reports `php@8.3 — not installed, skipping`
> (and still exits 0). The error text is reasonable but does not list which php
> versions *are* supported.

**Fix**
> Reconcile detector/resolver coverage for php: support php 8.3 (and other
> active majors) in `resolvePhp`/`fullVersion`, or have the detector snap to the
> highest resolver-supported version while warning. Have `status`/`add` enumerate
> supported versions. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-015 — A genuinely-installed `php-8.3.21` is invisible to `status`/`up`/`add` but shown installed by `services ls`

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / reporting consistency (install-state check)
- **Source:** exploratory (EXPLORE-032)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w4-1

**Steps to reproduce**
1. `~/.rawenv/store/php-8.3.21/` exists with a valid `.rawenv-installed` marker
   (a real, complete PHP 8.3.21 build).
2. With `rawenv.toml` declaring `php = "8.3"`, run `rawenv status`,
   `rawenv services ls`, and `rawenv up` back to back.

**Expected**
> All three commands agree on whether php is installed, and an installed
> `php-8.3.21` satisfies a `php = "8.3"` requirement.

**Actual**
> - `rawenv services ls` → `php  8.3  installed`.
> - `rawenv status` → `php  8.3  not installed` (`"installed": false`) with a
>   "binary not installed" warning.
> - `rawenv up` → `php@8.3 — not installed, skipping`.
> Root cause: `status`/`up` resolve the config version through
> `resolveVersion`/`fullVersion` and then call `store.isInstalled(name, version)`,
> which checks for an **exact** store dir `php-{version}/.rawenv-installed`.
> Because `fullVersion` has no `php "8.3"` mapping (see QF-014), it falls back to
> the bare `"8.3"` and looks for `php-8.3` — which does not exist; the real dir is
> `php-8.3.21`. Meanwhile `services ls` scans the store via `listInstalled` and
> matches by name, so it correctly finds `php-8.3.21`. `node "22"` is consistent
> only because `fullVersion` happens to map it to `22.15.0` (the exact dir name).
> This is the same divergence as QF-006, now demonstrated against a real
> installed runtime: there is no prefix/semver fallback in `isInstalled`.

**Fix**
> Give the three commands one source of truth for install state: have
> `isInstalled` (or `getStorePath`) resolve a config major like `8.3` to the
> newest installed `php-8.3.*` dir (prefix/semver match), or route all status
> checks through `listInstalled`. Pending. (Rolls up with QF-006; unblocked by
> fixing QF-014's version mapping.)

**User story:** n/a (minor; rolls up with QF-006)

---

> **Exploratory run context (EXPLORE-033):** Same real CLI rebuilt from this
> worktree (`zig build`, Zig 0.16.0, macOS arm64, binary at `zig-out/bin/rawenv`)
> and run against the live project `/Volumes/Projects/zelkai-trends` — a **real,
> dual-language monorepo**. Its JS side is a pnpm workspace (`package.json`
> `engines.node >= 22`, `pnpm-workspace.yaml` with `packages/*` + `apps/*`,
> Cloudflare Workers). Its Python side is a modern **`uv` workspace**: a root
> `pyproject.toml` (`requires-python = ">=3.11"`, `[tool.uv.workspace]` member
> `packages/scraper`), a 122 KB `uv.lock`, and a populated `.venv/`. There is
> **no `requirements.txt`**, **no `docker-compose.yml`**, and only a committed
> `.env.example` (the real `.env` is gitignored and absent). Flow exercised:
> `detect` (+`--json`) → `init` → `status` (+`--json`) → `services ls` → a
> controlled detector A/B/C test → `add python@3.12`. No crashes occurred. Side
> effects (the generated `rawenv.toml` and an empty `python-3.12.11/` store dir
> from the failed download) were cleaned up afterward; the project and store were
> left as found.
>
> The store already contained a real `node-22.15.0` (with `.rawenv-installed`),
> so node reported `installed` end-to-end and `status` printed **"No issues
> detected"** — despite the entire Python half of the project being invisible.
>
> Reproduced from EXPLORE-030/031: **QF-001** (the `execve`-without-PATH download
> bug), here against a **`python` runtime** — `add python@3.12` failed in **16 ms**
> while `github.com` was reachable, confirming the request never hit the network.
> This is the fourth project to hit QF-001 and the first to hit it for python.

### QF-016 — Python projects using `pyproject.toml` / `uv.lock` (no `requirements.txt`) detect zero Python runtime

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector (Python manifest coverage)
- **Source:** exploratory (EXPLORE-033)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w5-1

**Steps to reproduce**
1. In `/Volumes/Projects/zelkai-trends`, run `rawenv detect --json`. The project
   has a root `pyproject.toml` (`requires-python = ">=3.11"`, a `uv` workspace),
   a `uv.lock`, and a populated `.venv/` — but **no `requirements.txt`**.
2. Run `rawenv init` then `rawenv status`.
3. Controlled A/B/C test in a temp dir:
   - `pyproject.toml` only → `{"runtimes":[],"services":[]}`
   - `uv.lock` only → `{"runtimes":[],"services":[]}`
   - `requirements.txt` only → `{"runtimes":[{"name":"python","version":"3.12"}],...}`

**Expected**
> A project that declares Python via `pyproject.toml` (PEP 621 `requires-python`)
> and/or `uv.lock` is detected as needing a `python` runtime, just like one with
> a `requirements.txt`.

**Actual**
> `rawenv detect --json` → `{"runtimes":[{"name":"node","version":"22"}],"services":[]}`
> — Python is **completely missing**. `rawenv init` writes a `rawenv.toml` with
> only `node = "22"`, and `rawenv status` then prints **"No issues detected."**,
> giving false confidence that a half-Python project is fully covered. The
> resolver *does* support python (`resolvePython`, `python "3.12" → 3.12.11`), so
> this is purely a detector gap, not a runtime-support gap.

**Fix**
> Root cause: `detectRuntimes` in `src/core/detector.zig` only triggers python on
> `readFile(... "requirements.txt")`. Add detection for `pyproject.toml` (parse
> `requires-python` / `[tool.poetry.dependencies].python` and snap to a supported
> major) and `uv.lock`/`Pipfile`/`setup.py`/`.python-version`. `pyproject.toml` +
> `uv` is now the mainstream Python layout, so this misses most modern Python
> projects. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-017 — Service detection only reads `.env`, ignoring the committed `.env.example`

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector (env service parsing)
- **Source:** exploratory (EXPLORE-033)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w5-1

**Steps to reproduce**
1. In zelkai-trends, the real `.env` is gitignored/absent; only `.env.example`
   is committed (the standard convention).
2. Run `rawenv detect --json` / `rawenv services ls`.

**Expected**
> When no `.env` exists, the detector should fall back to `.env.example` (and/or
> `.env.*` templates) so service hints in the committed template are surfaced —
> at minimum as a suggestion.

**Actual**
> `detectRuntimes` calls `readFile(... ".env")` only; with no `.env` present,
> `parseEnvServices` never runs and `services = []`. Note this is partly correct
> here (zelkai-trends' services are Cloudflare Workers/Ollama, not DB URLs
> `parseEnvServices` recognizes), but the broader gap is real: the **only**
> committed env file is never inspected. `parseEnvServices` also only matches
> `DATABASE_URL=`/`REDIS_URL=`/`REDIS_HOST=`, so even a populated template with
> other conventions would yield nothing.

**Fix**
> Fall back to `.env.example`/`.env.template`/`.env.sample` when `.env` is
> absent, and broaden the key/value patterns `parseEnvServices` recognizes.
> Pending. (Low impact: workaround is to copy `.env.example` → `.env`.)

**User story:** n/a (minor)

---

> **Exploratory run context (EXPLORE-034):** Same real CLI rebuilt from this
> worktree (`zig build`, Zig 0.16.0, macOS arm64, binary at `zig-out/bin/rawenv`)
> and run against the live project `/Volumes/Projects/gratis` — a **real,
> large modular WordPress plugin suite** (40+ `gratis-*` plugins + a block
> theme). The deployable unit is `gratis-suite/`, which carries a real
> `docker-compose.yml` (a custom `wordpress` image built from a `Dockerfile`
> based on `wordpress:7-php8.3-apache`, plus `db: mariadb:11` and
> `redis: redis:7-alpine`), a `composer.json` (`phpredis/phpredis`,
> `awesome/simdjson_plus` — **no `php` constraint**), a `.env`
> (`COMPOSE_PROJECT_NAME=gratis` only), and a hand-written `rawenv.toml`
> (`php 8.4`, `mariadb 11`, `redis 7`). Flow exercised at the repo root
> (`/Volumes/Projects/gratis`) and inside `gratis-suite/`: `detect` (+`--json`)
> → `init` → `status` (+`--json`) → `services ls` → `connections` →
> `add mariadb@11` → `add php@8.4` → `add redis@7` → `up`. **No crashes occurred
> in any command** (every invocation exited cleanly; `up` exited 0 even on
> failure — see QF-012). All side effects (the empty `php-8.4.11/` store dir
> from the failed download, plus `~/.rawenv/certs/gratis-suite/` and
> `~/.rawenv/proxy/gratis-suite.Caddyfile` written by `up`) were cleaned up
> afterward; the project's `rawenv.toml` was left byte-identical and `init`
> correctly **skipped** the existing config.
>
> The store already contained real `php-8.4.0` and `php-8.3.21` runtimes (both
> with `.rawenv-installed` markers), which again made the install-state and
> version-mapping gaps reproducible against real installed binaries.
>
> Reproduced from earlier runs: **QF-001** (`add php@8.4`→`php@8.4.11` and
> `add redis@7`→`redis@7.4.0` both failed **instantly** — 32 ms — while
> `github.com` returned HTTP 200 in 1.9 s: the `execve`-without-PATH bug, now on
> a **fifth** project), **QF-005** (`up` printed `▶ redis@7.4.0 started` then
> `✗ redis (port 6381) failed: not ready after 30s` for an uninstalled binary),
> **QF-006/QF-015** (a real installed `php-8.4.0` shows `installed` in
> `services ls` but `not installed` in `status`/`up`, because `fullVersion`
> maps `php 8.4 → 8.4.11` and `isInstalled` looks for the non-existent
> `php-8.4.11` dir; redis version `7`→`7.4.0` across commands), and **QF-012**
> (`up` exited **0** despite redis failing to start, after blocking 30 s).

### QF-018 — `composer.json` with no `php` constraint defaults to php 8.4, ignoring the Dockerfile's pinned `php8.3` (detected runtime ≠ project's real PHP)

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector (PHP version source)
- **Source:** exploratory (EXPLORE-034)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w6-0

**Steps to reproduce**
1. In `/Volumes/Projects/gratis/gratis-suite`, run `rawenv detect --json`. Its
   `composer.json` `require` block lists only `phpredis/phpredis` and
   `awesome/simdjson_plus` (no `php` key). Its `Dockerfile` builds
   `FROM wordpress:7-php8.3-apache` (the real runtime is **PHP 8.3**).
2. Observe the detected runtime.

**Expected**
> The detected php version reflects the project's real PHP (8.3, as pinned by
> the Dockerfile base image) — or, when no constraint is discoverable, rawenv
> emits a clearly-labeled fallback rather than asserting a specific major.

**Actual**
> `{"runtimes":[{"name":"php","version":"8.4"}],...}` — php is reported as
> **8.4**, the project's actual runtime is **8.3**. Root cause:
> `detectRuntimes` in `src/core/detector.zig` does
> `.value = parsePhpVersion(allocator, data) orelse "8.4"`, and `parsePhpVersion`
> only reads `require.php` from `composer.json`. With no `php` key it returns
> `null` and the hard-coded `"8.4"` default wins. The `Dockerfile` base image
> tag (`php8.3`) — the authoritative version signal for a containerized
> WordPress app — is never consulted. WordPress/Sail-style projects very
> commonly pin PHP via the image rather than `composer.json`, so this
> mis-detects the primary runtime for a large class of real projects. Combined
> with QF-015, the mis-detected `8.4` is then also reported `not installed` by
> `status` even though `php-8.4.0` is in the store.

**Fix**
> Treat the hard-coded `"8.4"` as a clearly-labeled last resort, and add a
> Dockerfile/base-image version source (parse `php8.3` from
> `FROM wordpress:*-php8.3-*` and `FROM php:8.3-*`). Optionally read
> `config.platform.php` from `composer.json` and a `.php-version` file. Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-019 — `mariadb` is detected from compose and written to `rawenv.toml`, but the resolver has no `mariadb`/`mysql` package, so it can never be installed

- **Date:** 2026-06-10
- **Severity:** 🟠 Major
- **Status:** open
- **Area:** CLI / detector ↔ resolver mismatch (install path)
- **Source:** exploratory (EXPLORE-034)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w6-0

**Steps to reproduce**
1. In `gratis-suite` (compose `db: image: mariadb:11`), `rawenv detect` reports
   `mariadb 11` and the hand-written `rawenv.toml` declares `mariadb = "11"`.
2. `rawenv status` prints `⚠ mariadb: binary not installed — run
   rawenv add mariadb@11`.
3. Run `rawenv add mariadb@11`.

**Expected**
> A service the detector recognizes and `status` recommends installing
> (`rawenv add mariadb@11`) must be installable. MariaDB/MySQL is the primary
> database of essentially every WordPress, Laravel, and classic-LAMP project.

**Actual**
> `rawenv add mariadb@11` → `Unknown package: mariadb. Available: node, postgres,
> redis, python, php, meilisearch` (exit 1). The detector matches `mariadb`/
> `mysql` images (`src/core/detector.zig` `parseDockerComposeServices`), and
> `resolver.zig` has a `postgres` entry — but **no `mariadb` and no `mysql`**.
> So rawenv detects the DB, advertises an install command, then rejects it, and
> `rawenv up` reports `mariadb@11 — not installed, skipping`. This is the same
> class as QF-002 (mssql) and QF-009 (bun) — a runtime/service the tool surfaces
> but cannot resolve — now for the single most common dev database. Note
> `mariadb` (unknown service type) is **skipped** by `up`, whereas `redis` (a
> known service type) gets the QF-005 false-"started" + 30 s probe, so the two
> are also handled inconsistently.

**Fix**
> Add `mariadb` and `mysql` resolver entries (+ `resolveMariadb`/`resolveMysql`
> dispatch and `available_packages` listing). Until then, `status`/detector
> should not emit an `add mariadb@…` suggestion for an unresolvable service.
> Pending.

**User story:** _required — convert before VERIFY-040_

---

### QF-020 — A compose service with no published `ports:` reports `port: 0` in `detect` and a placeholder `1024` in `status`; redis's published host port `6380` is also dropped

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector + status (port reporting)
- **Source:** exploratory (EXPLORE-034)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w6-0

**Steps to reproduce**
1. In `gratis-suite`, the compose `db` service (`mariadb:11`) declares **no**
   `ports:` mapping; the `redis` service maps `- "6380:6379"`.
2. Run `rawenv detect --json` then `rawenv status --json`.

**Expected**
> Ports are reported consistently and meaningfully: an unpublished service
> falls back to its well-known default (mariadb → 3306), and a published
> mapping surfaces the **host** port the developer actually connects to
> (redis → 6380).

**Actual**
> - `mariadb`: `detect` → `"port":0`; `status` → `1024` (placeholder). Neither
>   is the real/default 3306.
> - `redis`: `detect` → `6379` (the container-side port, not the host `6380`);
>   `status`/`up` → `6381` (conflict-avoidance remap). The actual published host
>   port `6380` never appears anywhere.
> So for one project the same two services show four different ports across
> `detect`/`status`/compose, none matching what a developer would use. Extends
> QF-006 with the new `port: 0` (unpublished service) and host-vs-container
> (`6380:6379`) cases.

**Fix**
> When a compose service has no `ports:`, fall back to the service's default
> port; when it has `"<host>:<container>"`, report the **host** port. Centralize
> port resolution so `detect`/`status`/`up` agree. Pending. (Rolls up with
> QF-006.)

**User story:** n/a (minor; rolls up with QF-006)

---

### QF-021 — `connections` shows "No service dependencies found" even though compose declares `depends_on` (init flattens services and drops dependencies)

- **Date:** 2026-06-10
- **Severity:** 🟡 Minor
- **Status:** open
- **Area:** CLI / detector → init → connections (dependency map)
- **Source:** exploratory (EXPLORE-034)
- **Environment:** macOS arm64, Zig 0.16.0, rawenv built from worker-w6-0

**Steps to reproduce**
1. `gratis-suite`'s compose declares `wordpress.depends_on: [db, redis]` and
   `wpcli.depends_on: [db]`.
2. Run `rawenv connections`.

**Expected**
> The dependency map reflects the compose `depends_on` edges (e.g. the app
> depends on mariadb + redis), so `connections` and `down`'s reverse-dependency
> ordering have real data to work with.

**Actual**
> `rawenv connections` → `No service dependencies found.` The detector emits a
> flat list of services and `init` writes a flat `[services]` table with no
> `depends_on`, so the compose dependency graph is lost at import time and
> `connections` has nothing to show. (Benign here, but the dependency-aware
> `up`/`down` ordering the README advertises can never trigger for an
> init-from-compose project.)

**Fix**
> Capture `depends_on` during compose parsing and persist it into `rawenv.toml`
> (e.g. `[services.app] depends_on = [...]`), so `connections`/`down` can use
> it. Pending.

**User story:** n/a (minor)

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-10 | Log created and initialized (QA-050). |
| 2026-06-10 | EXPLORE-030: first exploratory run (qwik-fullstack end-to-end). Logged QF-001 (blocker), QF-002/QF-003 (majors), QF-004/QF-005 (minor), QF-006 (trivial). |
| 2026-06-10 | EXPLORE-030 quality check: logged QF-007 (blocker) — `tests/service_test.zig` corrupted with ANSI codes, `zig build test` fails to compile. |
| 2026-06-10 | EXPLORE-031: second exploratory run (rentflowiq, greenfield Bun/SolidStart). Logged QF-008 (major, `app` treated as package), QF-009 (major, bun unsupported by resolver), QF-010 (minor, meilisearch compose detection), QF-011 (minor, greenfield/packageManager), QF-012 (major, `up` exits 0 on total failure). Reproduced QF-001/QF-004/QF-005/QF-006 on a second project. |
| 2026-06-10 | EXPLORE-032: third exploratory run (rahcolours-b2b2c, real Laravel 11 / PHP 8.3 + Node/Vite with Laravel Sail compose). Logged QF-013 (major, quoted compose images detect zero services), QF-014 (major, php 8.3 detected but resolver only supports 8.4 — primary runtime uninstallable), QF-015 (minor, installed php-8.3.21 invisible to status/up/add). Reproduced QF-003/QF-006 patterns on a third project. |
| 2026-06-10 | EXPLORE-033: fourth exploratory run (zelkai-trends, real Node 22 + Python `uv`/`pyproject.toml` monorepo). Logged QF-016 (major, Python detected as zero — detector only reads `requirements.txt`, ignores `pyproject.toml`/`uv.lock`), QF-017 (minor, service detection ignores committed `.env.example`). Reproduced QF-001 for a `python` runtime (16 ms instant download failure while network was up) on a fourth project. |
| 2026-06-10 | EXPLORE-034: fifth exploratory run (gratis, real 40+-plugin WordPress suite; `gratis-suite/` runs PHP via a `wordpress:7-php8.3-apache` Dockerfile + mariadb:11 + redis:7-alpine). Logged QF-018 (major, composer.json without a php constraint defaults to php 8.4, ignoring the Dockerfile's php8.3), QF-019 (major, mariadb detected + recommended but unresolvable — `Unknown package: mariadb`), QF-020 (minor, port reporting: `port:0` for unpublished service / placeholder 1024 / dropped host port 6380), QF-021 (minor, `connections` empty because `init` drops compose `depends_on`). Reproduced QF-001/QF-005/QF-006/QF-012/QF-015 on a fifth project. **Full 5-project run completed with zero crashes.** Wrote `docs/exploratory-report.md` (consolidated cross-project report). |
