# DESIGN.md — Architecture & Design Decisions

Living record of how rawenv's detection, resolution, and GUI fit together, plus the
design decisions (and corrections) that shaped them. Pairs with `RULES.md` (process
rules) and `AGENTS.md` (agent bible). Update this when a design decision changes.

---

## 1. Stack detection (`src/core/detector.zig`)

`detect(allocator, dir)` returns `{ runtimes, services }`. It composes evidence from,
in order:

1. **Root manifests** — `package.json` (node/bun + `engines`), `composer.json` (php +
   WordPress fingerprint), `Cargo.toml` (rust), `go.mod` (go), `pyproject.toml`/
   `requirements.txt` (python), `Gemfile` (ruby).
2. **`.env` / `.env.example`** — service hints (postgres/mysql/redis from URLs).
3. **`docker-compose.yml`** — services from recognized `image:` tags (postgres, redis,
   mysql, mariadb, mongo, mssql, meilisearch), with `depends_on` edges.
4. **Dockerfile `FROM` base image** — the build runtime. Resolved from the compose
   service's `build: dockerfile:` (or root `Dockerfile`). Maps base images to a
   runtime+version: `dunglas/frankenphp:php8.5` → `frankenphp 8.5`; `wordpress:6-php8.3`
   → `php 8.3`; `php/node/python/ruby/go/bun` bases too. **Authoritative over a manifest
   default** (overrides the composer php version).
5. **WordPress inference** — a WordPress fingerprint in composer (wpcs,
   phpcompatibility-wp, roots/johnpbloch wordpress, wpackagist, `wordpress-*` type)
   implies PHP + a MySQL-compatible **database** — *unless one was already detected*.

### Invariants (learned the hard way — see §6)
- **Only emit installable entries.** Every emitted runtime/service must be a known
  resolver package (else `rawenv add` dead-ends). Embedded stores (SQLite via
  `pdo_sqlite`) are **not** emitted as services — they have no installable server.
- **Real identity, not the generic.** FrankenPHP is emitted as `frankenphp` (its own
  runtime) and **supersedes** a composer-detected `php` (the duplicate is removed) —
  it embeds PHP, so listing both is wrong.
- **Nested stack root** — the GUI's `ProjectSetupVM.resolveStackRoot` walks one level
  down for a compose file (e.g. `gratis/` → `gratis-suite/`) and runs detection there,
  because monorepos keep compose/.env in a subdirectory.

> Zig 0.16 note: directory *iteration* needs an `Io` the CLI doesn't construct (it uses
> a custom stdout writer + `std.posix`/`std.c`). The detector reads files via
> `std.posix.openat`; subdir-walking in the CLI is deferred — the GUI does the
> stack-root resolution in Swift instead.

## 2. Resolver / installer (`src/core/resolver.zig`)

`resolve(name, version)` → `{ name, version, url, sha256, archive_type }`. Packages and
their download sources:

| Package | Source | Notes |
|---|---|---|
| node | nodejs.org | SHASUMS256 published (pinned) |
| bun | GitHub releases (zip) | compute-on-download |
| postgresql | (prebuilt) | 16/17/18 |
| redis | (prebuilt) | 7 / 7.4 |
| python | (prebuilt) | 3.12 |
| **php** | **dl.static-php.dev** | 8.1–8.4 + **8.5 → 8.5.7** |
| meilisearch | GitHub releases (binary) | 1.12 |
| mariadb / mysql | MariaDB Foundation archives | linux-x86_64 only; `mysql` → MariaDB |
| **frankenphp** | **GitHub releases (single binary)** | Caddy + embedded PHP; v1.12.4; mac/linux × x86_64/arm64; versioned by the PHP line it serves |

**Detection ↔ installer is one contract** — adding detection for a version/tool means
adding the resolver package/version in the same change. `available_packages`,
`availableVersions`, the dispatch in `resolve`, and `fullVersion`/`phpFullVersion` are
kept in sync.

## 3. GUI (`gui/macos`, SwiftUI + MVVM)

- **Discovery → Setup** (`ProjectsView` + `ProjectSetupVM`): scan projects →
  `resolveStackRoot` → `rawenv detect --json` there → show runtimes + services. **Set
  Up Environment** installs detected **runtimes *and* services**, then `rawenv up`,
  with an `isSettingUp` progress state and the live CLI log; the final `rawenv up`
  error is surfaced (not swallowed). A **Back** button returns to the project list.
- **Dashboard** (`DashboardVM`): loads services for the active project. A project with
  no `rawenv.toml` raises `EnvironmentNotReadyError` → a **calm `.empty` state** ("not
  set up yet" + a "Set up environment" CTA via an injected `onSetUp` closure), *not* a
  raw decode error. Genuine failures still surface as `.failed`.
- **Settings → Runtimes**: install flow has a version **Picker** (`RuntimeCatalog`),
  per-row progress, and an **install-log popup**; `RuntimeManaging.install` returns the
  CLI log and throws `RuntimeInstallError` (with the log) on non-zero.
- **Navigation**: prefer injected closures with safe defaults over
  `@EnvironmentObject` so views render standalone in tests without crashing.
- **CLI binary**: the app bundles `Contents/Resources/rawenv` (preferred) and falls
  back to `~/.rawenv/bin/rawenv` / `/usr/local/bin`; the post-commit hook rebuilds the
  app so the bundled CLI tracks source.

## 4. Quality workflow

- **Local AI review before commit** (no PR): `coderabbit review --plain --type
  uncommitted` (pass `CODERABBIT_API_KEY` from `~/.zshrc`, never echo it) and/or
  `codex review --uncommitted` (ChatGPT-authed, agentic). Fall back to the other if one
  backend is down. Amazon Q stays a PR-only reviewer (no non-interactive local mode).
- **Local git hooks** (`.githooks/`) gate commit/push: format/lint, `zig build` +
  `zig build test`, `swift test`, and the quality guardrails (no hardcoded paths /
  masked failures / unpinned actions, scanning only added diff lines). Never bypassed.

## 5. Deploy wizard foundation (`gui/macos/.../DeployWizardVM.swift`)

Tested core only so far: SSH `DeployTarget` + store, triggers (manual/on-commit/
on-push), CI providers (GitHub/GitLab/Bitbucket) + pipeline paths, mode
(ci-pipeline vs rawenv-managed), `ServerCapabilities` → `recommendedApproach`
(terraform > ansible > docker > rawenv-agent), and `ServerIntrospecting` (stub).
**Deferred backends**: SSH transport + live `command -v` introspection, pipeline-file
generation, rawenv-managed deploy + change monitoring.

## 6. Decision log / corrections (2026-06)

- **php 8.5**: detector found it but the resolver capped at 8.4 → install dead-end.
  Fix: add 8.5 (static-php.dev 8.5.7) in the same spirit as "detection ↔ installer".
- **FrankenPHP**: was flattened to `php`. Fix: detect `frankenphp` as its own runtime,
  supersede the composer `php`, and add a `frankenphp` resolver package (single binary).
- **SQLite**: briefly emitted as a service → "Unknown package" on install. Fix: don't
  emit embedded stores as installable services.
- **Scanner regression**: removing the hardcoded `/Volumes/Projects` scan root (a
  guardrail cleanup) broke discovery (0 projects). Fix: enumerate `/Volumes/*`
  generically — a machine-specific *functional default* must be replaced, not deleted.
- **Setup "flicker"**: `setUpAll` installed only services → no-op for runtime-only
  projects. Fix: install runtimes too + progress.
- **Scary dashboard error**: a not-set-up project leaked a decode error. Fix: calm
  not-set-up empty state.
- **Process**: a push was blocked by `zig build test` failing while a `| tail` pipe
  hid the failure (`$?` was tail's). Verify against the rebuilt artifact and never read
  `$?` after a pipe.
