# QA Notes — rawenv macOS GUI Production-Readiness

Date: 2026-06-17 · Tester: automated agent (computer-use + CLI + test suite) · Iteration 1 of 5.
Under test: `zig-out/bin/rawenv` **0.2.0**; `/Applications/Rawenv.app` (rebuilt 12:36 by the post-commit hook).

## Phase 0 — Setup & baseline
- `rawenv --version` → **0.2.0** for all three: zig-out CLI, app-bundled CLI
  (`Rawenv.app/Contents/Resources/rawenv`), PATH `rawenv`. **App-bundled CLI is NOT stale.**
- `Rawenv.app` installed (Jun 17 12:36). `open -a Rawenv` → exactly **1** process
  (`pgrep -x Rawenv` = 1). No fork-storm / Dock flood — the prior crash-loop is fixed.
- `scripts/install-macos.sh` + `gui/macos/scripts/build-app.sh` (read): non-interactive
  (`set -euo pipefail`, no `read`/`sudo`); CLI→`~/.rawenv/bin`, app→`/Applications`;
  SHA-256-verifies both copies; ad-hoc signs when no Developer ID; strips quarantine;
  refuses to install if the embedded CLI == GUI binary (guards the self-exec bug).

## Phase 1 — GUI (computer use + tests)
- Live launch screenshot `qa/screenshots/01-launch-apple-music-prompt.png`: Dashboard renders —
  sidebar [Dashboard, Discovery, AI Chat, Connections, Deploy, Tunnel, Uninstall, Settings],
  Services [Start All / Stop], stat cards [CPU 0%, Memory, Running 0/0],
  detail tabs [Logs, Config, Connection, Cell, Backups].
- **Apple Music TCC prompt** appeared on launch ("Rawenv would like to access Apple Music, your
  music and video activity, and your media library"). Investigated:
  - 0 media APIs in `gui/macos/Sources` (grep MediaPlayer/MusicKit/MPMediaLibrary/ScriptingBridge/AVAudio).
  - 0 `NS*UsageDescription` in the installed Info.plist (`plutil -p`); none in `project.yml`;
    `NSAppleMusicUsageDescription` absent repo-wide.
  - Entitlements clean (app-sandbox, network.client, user-selected files only).
  - `tccutil reset MediaLibrary io.rawenv.app` **succeeded** (a record existed) → relaunch → **no prompt**.
  - **Conclusion: stale TCC entry from a prior experimental build — NOT a shipping bug. P3 dev-machine artifact.**
- Test suite (RAWENV_BINARY = zig-out CLI):
  - Unit: **407 tests / 86 suites PASS** (10s).
  - Full (unit + non-UI E2E): **641 tests / 119 suites PASS** (26s, exit 0); 11 UI-gated tests
    skipped (expected). No real failures. Covers FrankenPHP nested-detection E2E, FindAndSetup,
    Lifecycle, ProjectCreation, ServiceMigration/Validation, DeployEngine/View, all ViewModels.
- UI E2E (`ComprehensiveUIE2ETests`, `UIE2ETests`): drive **every** screen/tab/button/field/
  picker/toggle in the real app via the **Accessibility API** against `.build/debug/Rawenv`,
  gated by `RAWENV_RUN_UI_E2E=1`. They hijack the screen + need Accessibility permission →
  **must run on an idle host or the Tart VM**. NOT run on the active host (user in session) →
  deferred to the test-runner VM.

## Phase 2 — Detection sweep (12 real projects, `rawenv detect --json`)
| Project | Detected | Actual | Verdict |
|---|---|---|---|
| gratis (root) | php 8.4 + mysql 8 | FrankenPHP 8.5 + SQLite (in `gratis-suite/`) | **WRONG (P1)** — CLI ignores nested stack root |
| gratis/gratis-suite | frankenphp 8.5, no services | FrankenPHP 8.5 + SQLite (embedded) | **CORRECT** |
| mcp-for-page-builders | rust stable | Rust (Cargo.toml) | OK (compose.test.yml services not emitted) |
| qwik-fullstack | bun 1 + redis 7 + mssql 2022 | Bun/Node + redis + mssql | Plausible |
| rahcolours-b2b2c | node 22 + php 8.3 + redis 7 + mysql 8 | Laravel + Node | Plausible |
| chargeback-intelligence-mini-api | empty | empty dir | CORRECT |
| agent-router-swift | empty | Swift (Package.swift) | **GAP (P3)** — SPM unsupported |
| rentflowiq | empty | docs + has `rawenv.toml` | CORRECT (no manifest) |
| proweb-group | empty | HTML/content | CORRECT |
| gotassql | empty | FoxPro (.prg) | CORRECT (unsupported lang) |
| qwik-devtools | empty | browser ext (`manifest.json`) | borderline (no package.json) |

- Install resolution verified (this + prior session): `rawenv add php@8.5` → 8.5.7;
  `rawenv add frankenphp@8.5` → downloads; FrankenPHP nested-detection E2E green.
- **Deferred**: driving the GUI to actually install + `up` every project (downloads runtimes,
  mutates `~/.rawenv`, needs idle host or VM).
