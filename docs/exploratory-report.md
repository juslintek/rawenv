# rawenv Exploratory Test Report — 5 Real Projects

**Date:** 2026-06-10
**Build:** `zig build` (Zig 0.16.0), macOS arm64, binaries built per-worktree
from `worker-w2-0` … `worker-w6-0`.
**Method:** The real CLI (`zig-out/bin/rawenv`) was run end-to-end against five
**live, on-disk projects** — not fixtures. Each run exercised the full flow
(`detect` → `init` → `status` → `services ls` → `connections` → `add` → `up`),
logged findings to [`qa-findings.md`](qa-findings.md), and cleaned up every side
effect (generated `rawenv.toml`s, empty store dirs from failed downloads, TLS
certs, Caddyfiles). Per-finding detail (steps, root cause, fix) lives in
`qa-findings.md`; this document is the cross-project synthesis.

---

## The five projects

| # | Story | Project | Stack | Why it was chosen |
|---|-------|---------|-------|-------------------|
| 1 | EXPLORE-030 | `qwik-fullstack` | Qwik 2 + **bun** + MSSQL (azure-sql-edge) + Redis, docker-compose | Mature JS app; non-standard DB + bun toolchain |
| 2 | EXPLORE-031 | `rentflowiq` | **Greenfield** Bun + SolidStart + PostgreSQL + Redis + MeiliSearch | Planning-stage repo: hand-written `rawenv.toml`, no manifests/source yet |
| 3 | EXPLORE-032 | `rahcolours-b2b2c` | **Laravel 11** / PHP 8.3 + Node/Vite, Laravel **Sail** compose | Most common PHP dev stack; quoted compose images |
| 4 | EXPLORE-033 | `zelkai-trends` | Node 22 (pnpm) + **Python `uv`/`pyproject.toml`** monorepo, Cloudflare Workers | Dual-language; modern Python layout, no `requirements.txt` |
| 5 | EXPLORE-034 | `gratis` | **WordPress** suite (40+ plugins); `gratis-suite/` = php8.3 Dockerfile + **mariadb:11** + redis:7 | Large real WordPress/LAMP app; DB pinned via image, php via Dockerfile |

Together these span the four ecosystems rawenv targets (JS/bun, PHP, Python,
container/compose) plus a greenfield case — a deliberately broad surface.

---

## Headline result

- **Zero crashes across all 5 projects and every command.** No panics, no
  segfaults, no hangs (beyond the intended-but-buggy 30 s readiness probe). The
  binary is robust. This satisfies the EXPLORE-034 acceptance criterion "No
  crashes across the full 5-project run."
- **But the core value loop is broken end-to-end.** On **all five** projects the
  `detect → init → add/up` pipeline could not actually provision the stack,
  because of one blocker (QF-001) plus a recurring detector↔resolver mismatch.
- **21 findings logged** (QF-001…QF-021): **2 blockers, 10 majors, 6 minors,
  3 trivials.** Several reproduced on multiple projects, which is the strongest
  signal of where to invest.

---

## What worked

- **The CLI never crashed.** Every command on every project exited cleanly and
  produced output. Error paths degrade gracefully (e.g. DNS setup correctly
  detects it needs `sudo` and prints guidance instead of failing hard).
- **`detect` is genuinely useful for the common path.** It correctly read
  `package.json` engines (node), `composer.json`, `Cargo.toml`, `go.mod`,
  `requirements.txt`, `Gemfile`, and unquoted compose images. For gratis it
  cleanly produced `php`, `mariadb`, `redis` from the suite's compose +
  composer.
- **`init` is safe and idempotent.** It refuses to clobber an existing
  `rawenv.toml` (`already exists — skipping`), which protected the hand-written
  configs in rentflowiq and gratis.
- **`status`/`services ls`/`connections` are readable** and the `--json` output
  is clean and scriptable.
- **`up` does the right *peripheral* things:** it generated a self-signed TLS
  cert + a per-project Caddyfile and correctly flagged that `.test` DNS needs
  sudo. The reverse-proxy/TLS scaffolding works even when the services
  themselves don't start.
- **Real installed runtimes are detected by `services ls`.** When the store held
  genuine `node-22.15.0` / `php-8.4.0` / `php-8.3.21` builds, `services ls`
  found them by name.

## What's broken — cross-cutting themes

### 1. Install path is dead on arrival (QF-001 — BLOCKER, 5/5 projects)
`rawenv add` / `rawenv up` can **never** download a package. `runCommand` in
`src/core/store.zig` calls `std.c.execve` with a **bare** command name
(`"curl"`, `"tar"`, …); `execve(2)` does not search `PATH`, so the child dies
with ENOENT/`_exit(127)` and the parent reports a misleading "check your
connection" error. Reproduced on **every** project and for **every** runtime
type — node, postgresql, redis, **python**, **php** — always failing in
**16–32 ms** while the upstream URL returns HTTP 200 by hand. This single bug
makes the headline workflow non-functional everywhere. **Fix:** use `execvp`
(PATH-searching) or resolve absolute paths; and distinguish "exec failed" from a
real network error.

### 2. Detector ↔ resolver mismatch (QF-002/003/009/014/016/018/019 — 5/5 projects)
The detector advertises runtimes/services the resolver cannot install, so
`detect → init → add` is **internally inconsistent on every project**:

| Project | Detected / written / recommended | `rawenv add` result |
|---------|----------------------------------|---------------------|
| qwik-fullstack | `node 20` (from `>=20…`) ; `mssql` | node 20 unknown (only 22); mssql not detected at all |
| rentflowiq | `bun` (primary runtime) | `Unknown package: bun` |
| rahcolours | `php 8.3` (primary) | `Unknown version '8.3'` (only 8.4) |
| zelkai-trends | Python (via `pyproject.toml`/`uv.lock`) | **not detected** (only reads `requirements.txt`) |
| gratis | `php 8.4` (real is 8.3) ; `mariadb 11` | `Unknown package: mariadb`; php mis-versioned |

The pattern: **`status` recommends an `add` command the tool then rejects.** The
resolver knows only `node, postgres, redis, python, php, meilisearch` — missing
**bun, mariadb/mysql, mssql**, and it pins **single** versions (node 22, php
8.4) while detectors emit whatever the manifest says. The primary runtime/db of
**4 of the 5 real projects** could not be installed even if QF-001 were fixed.

### 3. Compose/manifest parsing gaps (QF-002/010/013/016/017/018/021)
The detector's compose parser is the weakest link and diverges from a second,
richer parser in `src/core/compose.zig`:
- Drops **quoted** image values (`image: 'mysql:8.0.39'`) → **zero** services
  for every Laravel Sail project (QF-013).
- No matcher for `azure-sql-edge`/`mssql` (QF-002), `getmeili/meilisearch`
  (QF-010).
- Ignores `depends_on`, so `connections` is always empty for compose imports
  (QF-021).
- Python only via `requirements.txt` — misses `pyproject.toml`/`uv.lock`, the
  modern default (QF-016).
- PHP version only from `composer.json require.php`; ignores the Dockerfile base
  image (`php8.3`) and defaults to `8.4` (QF-018).
- Only reads `.env`, never the committed `.env.example` (QF-017).

### 4. Install-state & version-mapping divergence (QF-006/015 — 3/5 projects)
`status`/`up` and `services ls` disagree about whether the same runtime is
installed, because `status`/`up` resolve a config major (`php 8.4`) through
`fullVersion` to an **exact** dir (`php-8.4.11`) and `isInstalled` does no
prefix/semver fallback — so a real `php-8.4.0`/`php-8.3.21` in the store reads as
"not installed" in `status` but "installed" in `services ls`. Versions and ports
also differ between commands (redis `7`↔`7.4.0`; ports `0`/`1024`/`6379`/`6380`/
`6381` for the same service). There is no single source of truth.

### 5. `up` reliability & exit codes (QF-005/012 — 3/5 projects)
`up` prints `▶ … started` for services whose binary was never installed, then
blocks **30 s per service** on a TCP probe before reporting failure — and still
**exits 0**. Any CI / `git push → deploy` automation (which the README leans on)
cannot detect that provisioning failed. Uninstalled services should be skipped
fast (as runtimes already are), and `up` should return non-zero on failure.

---

## Severity rollup (all 5 runs)

| Severity | IDs | Count |
|----------|-----|-------|
| ⛔ Blocker | QF-001 (install path), QF-007 (corrupt `service_test.zig`) | 2 |
| 🟠 Major | QF-002, QF-003, QF-008, QF-009, QF-012, QF-013, QF-014, QF-016, QF-018, QF-019 | 10 |
| 🟡 Minor | QF-004, QF-010, QF-011, QF-015, QF-017, QF-020 | 6 |
| ⚪ Trivial | QF-005, QF-006, QF-021 *(low-impact UX/consistency)* | 3 |

> Note: QF-005/QF-006 were originally filed minor/trivial; they recur on most
> projects, so treat them as higher-priority than their label suggests.

---

## Recommendations (in priority order)

1. **Fix QF-001 first.** It is a one-line class of bug (`execve` → `execvp`/
   absolute paths) that single-handedly unblocks `add`/`up` on all platforms and
   all five projects. Nothing else in the install/run loop can be validated
   until this lands. Also fix the misleading "check your connection" message.
2. **Fix QF-007** so `zig build test` compiles again (strip ANSI codes from
   `tests/service_test.zig`). The suite currently can't run, so regressions in
   the fixes below would go unnoticed.
3. **Close the detector↔resolver gap** (QF-002/003/009/014/018/019). Two
   sub-tasks: (a) broaden resolver coverage to the runtimes real projects use —
   **bun, mariadb/mysql**, php 8.1–8.3, node 20 LTS; (b) make the detector snap
   to the highest *resolver-supported* version and never recommend an `add`
   command the resolver will reject. Enumerate supported versions in error text.
4. **Unify compose/manifest parsing** (QF-013/002/010/016/017/021). Collapse the
   two compose parsers onto the richer `compose.zig`; strip quotes from `image:`;
   add mssql/meilisearch matchers; detect `pyproject.toml`/`uv.lock`; read the
   Dockerfile base image for PHP; fall back to `.env.example`; carry `depends_on`
   into `rawenv.toml`. QF-013 alone unblocks **all** Laravel Sail projects.
5. **Establish one source of truth for install-state, version, and port**
   (QF-006/015/020). Route `status`/`up`/`services ls` through the same
   prefix/semver-aware `isInstalled` and the same port resolver (host port for
   `h:c` mappings; default port for unpublished services).
6. **Make `up` honest** (QF-005/012): gate the readiness probe on an installed
   check (skip uninstalled services immediately) and return a non-zero exit when
   any required service fails to start.
7. **Handle first-party/logical services** (QF-008): services with `depends_on`
   and no resolver entry (e.g. the project's own `app`) should be marked
   "managed by you", not routed through the package resolver or flagged
   "binary not installed".

### Suggested story conversion before VERIFY-040
Per the QA process rule, all blockers + majors need stories: **QF-001, QF-007**
(blockers) and **QF-002, QF-003, QF-008, QF-009, QF-012, QF-013, QF-014, QF-016,
QF-018, QF-019** (majors). Many collapse into shared fixes — e.g. one
"resolver coverage" story covers QF-003/009/014/019/(018), and one "unify compose
parsing" story covers QF-002/010/013/016/021.

---

## Bottom line

rawenv's **UX shell is solid** — detection, config generation, status reporting,
TLS/proxy scaffolding, and crash-resistance all hold up against five real,
messy projects. The **provisioning core is not yet functional**: a single
blocker (QF-001) plus a systematic detector↔resolver/coverage gap mean the
advertised `detect → add → up` loop cannot actually stand up the stack for any
of the five. The fixes are well-scoped and mostly independent; QF-001 and the
resolver-coverage work would move rawenv from "promising demo" to "actually
provisions a real project."
