# QA Reviews — per-feature verdicts

Iteration 1 of 5 · 2026-06-17. Verdict: PASS / PARTIAL / DEFERRED / FAIL. Severity P0 (blocks
prod) … P3 (polish). Evidence keys: U=unit suite (407/86 pass), F=full suite (641/119 pass),
S=live screenshot, C=CLI output, R=code/script read.

| Area | Feature | Verdict | Sev | Evidence |
|---|---|---|---|---|
| Packaging | Build + install CLI+app, SHA verify, ad-hoc sign, quarantine strip | PASS | — | R install-macos.sh / build-app.sh; C versions 0.2.0 |
| Packaging | App-bundled CLI not stale | PASS | — | C: bundled == zig-out == PATH == 0.2.0 |
| Stability | Single-instance launch, no fork storm | PASS | — | S; `pgrep -x Rawenv` = 1 |
| Privacy | No media/Apple-Music access in shipping code | PASS | P3 | R (0 media APIs / plist keys / entitlements); tccutil reset → no prompt |
| Dashboard | Sidebar, stat cards, detail tabs render | PASS | — | S |
| Dashboard | Calm not-set-up state + CTA (no raw error) | PARTIAL | — | DashboardVMTests pass (U); live state not yet screenshot |
| Discovery | Scan, custom path, mounted volumes, 0-projects | PASS | — | ScannerEngineTests pass (U) |
| Projects/Setup | Detection incl. FrankenPHP php 8.5 (nested) | PASS | — | FrankenphpDetectionE2ETests (F); C gratis-suite |
| Projects/Setup | CLI detect at a monorepo root | **FAIL** | **P1** | C gratis root → php 8.4 + mysql (should be frankenphp 8.5) |
| Projects/Setup | Set Up Environment installs runtimes+services+`up` | PARTIAL | — | ProjectSetupVM / InstallFlowVM tests pass (U); full per-project GUI install DEFERRED |
| Settings | Runtimes install (version picker, log popup, install/remove) | PASS | — | SettingsVMTests / InstallFlowVMTests pass (U) |
| Settings | Network / Cells validation, General, AI, Theme, About | PARTIAL | — | VM tests pass (U); live tab walk-through DEFERRED to VM |
| Deploy | Wizard model, recommendation, branches | PASS | — | DeployEngine/DeployView/DeployFix/DeployWizardVM pass (U) |
| Detection | Swift / SPM (`Package.swift`) | **FAIL** | P3 | C agent-router-swift → empty |
| Detection | Empty projects (FoxPro/HTML/docs/empty) | PASS | — | C: correctly empty for unsupported manifests |
| GUI | Every control via AX UI E2E | DEFERRED | — | Suites exist (R); need idle host / Tart VM + AX permission |
| Suite | Unit + non-UI E2E | PASS | — | F: 641/119 pass, 0 fail, 11 UI skipped |

## Summary
- **0 P0**, **1 P1** (CLI nested-stack-root divergence), **1 P2** (WordPress→MySQL heuristic),
  P3 polish (privacy note, Swift detection, empty-detect feedback).
- Strongly covered by automated tests; the remaining gaps are the **live AX UI E2E** and
  **per-project GUI install**, both deferred to the Tart VM (screen-hijacking, mutates machine).

## Iteration 3 (Tart VM, live AX UI E2E) — updates

| Area | Feature | Verdict | Sev | Evidence |
|---|---|---|---|---|
| GUI | Every control exercised via AX UI E2E | **PASS** | — | `fullFlowEveryControlAndOption` PASSED in VM (was DEFERRED) — drives every screen/tab/control |
| Dashboard | Calm not-set-up state + CTA | **PASS** | — | `vm-03` screenshot: "This environment isn't set up yet" + "Set up environment →" |
| Dashboard | CLI-not-found error message | PARTIAL | P3 | `vm-02`: calm title + Retry, but raw "The file 'rawenv' doesn't exist" detail = **F-VM-1** |
| Stability | No crashes during full AX control sweep | PASS | — | UI E2E ran to completion; app launched/terminated cleanly each test |
| Suite | UIE2ETests are self-contained | **FAIL** | P2 | 3 tests assert `.loaded` but seed no project → `.empty` → false failures = **F-VM-2** |

**Criterion 1 status:** now **MET** — every control exercised via the AX `fullFlowEveryControlAndOption`
(passed) + screenshots of the loaded (host), failed (vm-02), and empty (vm-03) dashboard states.

## Iteration 4 (R1 fix) — updates

| Area | Feature | Verdict | Sev | Evidence |
|---|---|---|---|---|
| Projects/Setup | CLI detect at a monorepo root | **PASS** | — | commit 39ee475: gratis root → frankenphp 8.5 (was php 8.4 + mysql); nested-detect test runs |
| Detection | WordPress→MySQL not over-emitted (R2) | **PASS** | — | gratis root no longer emits mysql (descends to the authoritative nested stack) |
| Build | Windows cross-compile | PASS | — | `zig build -Dtarget=x86_64-windows` exit 0 after the AT.FDCWD guard |
| Testing | commands.zig tests actually run | **PASS** | — | fixed `main.zig` test block (`_ = commands;`); count 272→273 |

**P1 count now 0.** Only non-blocking P2/P3 polish remains (F-VM-2, F-VM-1, R3–R5).
