# GOAL — rawenv macOS GUI: Production-Readiness QA & Remediation

> Computer-use agent. Binding: work until all criteria are met with cited evidence.

## Mission
Verify the rawenv macOS SwiftUI app works flawlessly end-to-end via computer use:
build/install/launch it, **set up rawenv for every real project through the GUI**,
exercise **every screen, control, and feature**, screenshot evidence, document
findings, and produce a prioritized **remediation plan** for production-ready.
Drive the real app + CLI — never simulate.

## Operating rules (read `RULES.md` / `DESIGN.md` / `AGENTS.md`)
- **Never run the GUI/interactive cmds from the plain shell** (hangs) — drive via
  computer-use / the **test-runner (Tart VM)**; CLI: `</dev/null` + timeouts; hand
  sudo/login to the user.
- Never bypass git hooks; never mask failures; **never read `$?` after a pipe**
  (`set -o pipefail` / redirect-to-file).
- Code fixes: confirm branch → **local CodeRabbit+Codex review** → verify push (`git ls-remote` == local).
- Judge findings vs **detection↔installer** + **calm-UX** (RULES §11–§12).

## Phase 0 — Setup
1. `bash scripts/install-macos.sh`; confirm `rawenv --version` + the app-bundled CLI isn't stale. 2. Launch the app (computer-use); confirm no crash / single
   instance. 3. List real projects (diverse stacks): `gratis` (FrankenPHP php8.5·SQLite, nested
   `gratis-suite/`), `mcp-for-page-builders` (Rust), `qwik-fullstack` (Node), + Discovery.

## Phase 1 — Feature matrix (exercise EVERY control; screenshot; expected vs actual)
Valid + edge inputs; flag flicker, raw errors, crashes, no-ops, blocking UI.
- **Installer**: flow, progress, error+retry, port-change.
- **Discovery**: scan, force rescan, add path, scan full disk, `/Volumes/*`, 0-projects.
- **Projects/Setup**: Set Up →; detection incl. **FrankenPHP php8.5** (gratis); version
  pickers; **Set Up Environment** installs **runtimes + services** + `up`, with progress
  + real log + surfaced `up` errors; Back.
- **Dashboard**: services (run/stop), logs, config; **calm "not set up yet" + CTA** for
  uninitialized (never a raw error).
- **Settings tabs**: General, Services, **Runtimes** (version picker, per-row progress,
  install-log popup, install+remove), Network (port validation), Cells (limits), Deploy, AI (key reveal, autonomy), Theme, About.
- **AI Chat, Connections, Deploy wizard, Tunnel, Uninstall**; project switcher, Start
  All/Stop, theme, resize, accessibility identifiers.

## Phase 2 — Real-world setup (core)
Via the GUI, set up **all** projects: detect → install runtimes + services → `up` →
verify on Dashboard. Per project record detected vs **actual** stack (manifests,
Dockerfile `FROM`, compose `build:`, nested dirs, `.env`) + install outcome
(success / unknown package / version mismatch). File every gap with a repro.

## Phase 3 — Deliverables (under `qa/`)
1. `notes.md` — observations + screenshot refs. 2. `reviews.md` — per-feature
**PASS/FAIL** + severity (P0–P3) + evidence. 3. `feedback.md` — UX:
confusing states, missing affordances, copy, latency, a11y. 4. **`REMEDIATION.md`** —
prioritized; each item = problem · repro · impact · fix · acceptance, grouped by gate (Functionality, Detection/Install, UX, Stability, A11y, Packaging).

## Success criteria (cite evidence for each)
1. Every screen/control exercised + screenshot-documented. 2. Every real project set up
via the GUI; gaps captured with repro. 3. No crashes / raw-error leaks / no-op flicker
(or each filed P0/P1). 4. Four docs exist; `REMEDIATION.md` actionable, P0/P1 closure =
production-ready. 5. Final **go/no-go**, remaining P0 count (target 0).

## Loop
act → observe (screenshot + log) → verify vs expected → record → if broken, add a
`REMEDIATION.md` entry + fix. Iterate until the matrix + all projects are covered, then
synthesize `REMEDIATION.md` + go/no-go. Complete only when criteria are met with
evidence from this run.
