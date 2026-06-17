# REMEDIATION Plan — toward production-ready

Iteration 1 of 5 · 2026-06-17. Gates: Functionality · Detection/Install · UX · Stability/Perf ·
Accessibility · Packaging. **Status: 0 P0 · 1 P1 · 1 P2 · 4 P3.**

## P0 — blocks production
_None found this iteration._ Build, launch, the 641-test suite, and core detection/install are all green.

## P1 — must fix before GA

### R1. CLI doesn't resolve nested stack roots → wrong stack at a monorepo root
- **Gate:** Detection/Install.
- **Problem:** `rawenv detect / init / status` in `gratis/` reports php 8.4 + mysql 8; the real
  stack (FrankenPHP 8.5 + SQLite) lives in `gratis/gratis-suite/`. Only the GUI
  (`ProjectSetupVM.resolveStackRoot`) descends; the CLI does not. A CLI user configures the wrong
  runtimes/services and contradicts the GUI.
- **Repro:** `cd <gratis> && rawenv detect --json` →
  `{"runtimes":[{"name":"php","version":"8.4"}],"services":[{"name":"mysql",...}]}`; compare
  `cd <gratis>/gratis-suite && rawenv detect --json` → `{"runtimes":[{"name":"frankenphp","version":"8.5"}],...}`.
- **Impact:** Wrong `rawenv.toml`, wrong installs, user confusion.
- **Fix:** Port `resolveStackRoot` into the Zig detector — auto-descend one level when the root
  has no compose/Dockerfile but a single child does (or add `rawenv detect --recursive`).
  Supersede the root WordPress inference with the nested stack.
- **Acceptance:** `rawenv detect` at the gratis root reports `frankenphp 8.5` and no mysql; a new
  Zig detector test covers a nested compose + `Dockerfile.franken` fixture (mirror the Swift
  `FrankenphpDetectionE2ETests`).

## P2

### R2. WordPress→MySQL heuristic asserts MySQL even for SQLite stacks
- **Gate:** Detection. **Repro:** gratis root emits `mysql 8` from the WordPress fingerprint though
  the app runs SQLite. **Fix:** only infer the DB when the resolved (nested) stack has no explicit
  DB; once SQLite/embedded is found, don't add MySQL. **Acceptance:** gratis root (after R1)
  reports no mysql.

## P3

- **R3. Apple Music TCC prompt (stale dev TCC).** Shipping code clean. Document
  `tccutil reset MediaLibrary io.rawenv.app` for devs; add a packaging test asserting the built
  Info.plist has zero `NS*UsageDescription` and no media entitlement; consider a separate dev
  bundle id. **Acceptance:** packaging test green; clean-machine launch shows no prompt.
- **R4. Swift/SPM not detected** (agent-router-swift). Add `Package.swift` detection if Swift is in
  scope, else document the non-goal.
- **R5. Empty-detection has no user feedback.** Print "no supported manifest found (looked for …)"
  on an empty `detect`.
- **R6. Live GUI E2E + per-project GUI install not yet exercised on the host.** Run
  `ComprehensiveUIE2ETests` / `UIE2ETests` (`RAWENV_RUN_UI_E2E=1`) and drive per-project
  **Set Up Environment** in the **Tart VM** (test-runner agent) — screen-hijacking + machine-
  mutating, so not on the active host. **Acceptance:** AX UI E2E green in the VM + a screenshot
  per screen + each project installed and `up` once.

## Go / No-Go (iteration 1)
**Conditional GO for beta · NO-GO for GA until R1 (P1) ships.** No P0 blockers: the app builds,
launches cleanly (single instance), passes 641 tests across 119 suites, and the core
FrankenPHP / php-8.5 detection + install works through the GUI. The one must-fix is the CLI
nested-stack-root divergence (R1). To fully satisfy the QA contract, the remaining work is the
live AX UI E2E + per-project GUI installs in the Tart VM (R6) — planned for a later iteration.
