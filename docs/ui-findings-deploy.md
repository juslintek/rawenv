# UI Exploration Findings — Deploy

Task: **UI-004 — Explore Deploy: all tabs (terraform, ansible, containerfile, log), generate flow**

Scope: macOS SwiftUI app at `gui/macos`, the **Deploy** screen reached via the
sidebar (`nav_deploy` → `Destination.deploy`). Behavior was derived by reading
the shipping source — `Views/Deploy/DeployView.swift`, `ViewModels/DeployVM.swift`,
`Services/DeployEngine.swift`, `Services/DataStore.swift`, `App/AppState.swift` —
the unit/UI test suites, and the corresponding CLI handler
(`src/cli/main.zig` → `handleDeployGenerate`), compared against the interactive
design intent in `design/prototype/screens-deploy.js` (the canonical "what it
SHOULD do").

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · 🔌 CLI mismatch · 🔴 risk

---

## 0. TL;DR

- All **4** deploy tabs render and switch: terraform, ansible, containerfile,
  deployLog. ✅ (task scope matched exactly)
- There is **no explicit "Generate" button.** Config is generated implicitly on
  view load by shelling out to `rawenv deploy generate --json`. ❌
- Code tabs have **no syntax highlighting** (monochrome monospaced text), a
  **no-op Save button**, and **no "Deploy Now"/provider/format controls** that
  the prototype promises. ⚠️/❌
- **Empty / unconfigured state is a silent blank panel** — no message, no error,
  no "run `rawenv init`" hint. ❌
- **`▶ Start Deploy` executes a real `terraform apply -auto-approve`** in the
  process working directory with **no confirmation dialog.** 🔴
- The Deploy Log error box shows a **hardcoded "Redis port 6379" message** that
  is unrelated to the actual failure. ⚠️
- Deploy reads `rawenv.toml` from the **process CWD, not the active project** —
  switching projects in the sidebar does not change what Deploy generates. 🔴🔌

---

## 1. Screen anatomy

`DeployView` (`Sources/Rawenv/Views/Deploy/DeployView.swift`,
`accessibilityIdentifier("deploy_view")`) is a vertical stack:

1. **Tab bar** — pill `Button`s generated from `DeployViewTab.allCases`, each
   with id `deploy_tab_<rawValue>`. A trailing `Spacer()` left-aligns them.
2. **Divider.**
3. **Tab content** — a `switch activeTab` over `CodeTab` (×3) or `DeployLogTab`.

On appear, `.task { await viewModel.load() }` fetches the deploy config once.

Reachability: Deploy lives in `ContentView.detailView` and is only reachable
after install + setup completes (`isInstalled && hasCompletedSetup`); otherwise
the app shows the Installer / Projects screens instead.

### 1.1 Two conflicting `DeployTab` enums — finding ❌ (dead code)

There are **two** tab enums:

| Enum | File | Cases | Used by the View? |
|------|------|-------|-------------------|
| `DeployViewModel.DeployTab` | `DeployVM.swift` | terraform, ansible, containerfile (**3**) | **No** |
| `DeployViewTab` | `DeployView.swift` | terraform, ansible, containerfile, deployLog (**4**) | **Yes** |

The View keeps its own `@State private var activeTab: DeployViewTab` and never
reads `viewModel.selectedTab`. Consequently the VM members
`selectedTab`, `currentContent`, and `copyCurrentContent()` are **dead code from
the UI's perspective** — they are exercised only by `DeployVMTests`. The
`CodeTab` Copy button re-implements clipboard logic inline instead of calling
`viewModel.copyCurrentContent()`. The two surfaces also disagree on tab count
(3 vs 4), which is exactly the kind of drift that hides bugs.

---

## 2. Tab inventory & switching — ✅

`DeployViewTab.title` maps:

| rawValue (id) | Displayed label | Prototype label |
|---|---|---|
| `terraform` | Terraform | Terraform |
| `ansible` | Ansible | Ansible |
| `containerfile` | **Image** | **Image Build** |
| `deployLog` | Deploy Log | Deploy Log |

- ✅ Clicking a pill sets `activeTab` and swaps content. The active pill is
  bolded + `bgTertiary`-filled.
- ⚠️ Label drift: the containerfile tab is titled **"Image"**, while the
  prototype calls it **"Image Build"**. Minor, but inconsistent.
- Covered by `RawenvUITests.testDeployTabSwitching` and
  `ComprehensiveUIE2ETests` (loops all four `deploy_tab_*` ids).

---

## 3. Code tabs (terraform / ansible / containerfile) — `CodeTab`

Each renders: a header (`title` + **Copy** + **Save**) and a `ScrollView`
containing the code as monospaced `Text`.

| Acceptance criterion | Status | Notes |
|---|---|---|
| Code display | ✅ | `Text(code)` monospaced, `.textSelection(.enabled)`, native `ScrollView` (vertical). |
| **Syntax highlighting** | ❌ | Code is a single `Color.textPrimary` string. The prototype colors keywords (`--accent`) and string literals (`--warning`); the app is **monochrome**. The acceptance criterion is **not** met. |
| Copy button | ✅ | Writes `code` to `NSPasteboard`; label flips to "Copied!" for 1.5 s, then back to "Copy". Works — but **bypasses** `viewModel.copyCurrentContent()` (duplicated logic). |
| Scroll | ✅ | Native vertical scrolling. No horizontal scroll, so long Terraform lines wrap rather than scroll. |
| **Save button** | ❌ | `Button("Save") {}` — **empty closure, no-op.** Prototype's "Save to terraform/" pops a `showSaved()` modal listing written files. Here nothing happens and there is no feedback. |
| **Deploy/Run/Build action** | ❌ | Prototype gives each code tab a primary action ("🚀 Deploy Now" / "🚀 Run Playbook" / "🔨 Build Image") that jumps to the Deploy Log. The app's `CodeTab` has **only Copy + (dead) Save** — there is no way to trigger a deploy from a code tab; you must manually click the **Deploy Log** tab. |
| **Provider selector** | ❌ | Prototype shows a Hetzner / AWS / DigitalOcean / Custom SSH stats-row driving generation. The app has **none**; the provider is hardcoded to `hetzner` in the CLI and surfaces only as a static "Hetzner CX22" label in the log tab. |
| **Image format selector** | ❌ | Prototype's Image Build tab offers OCI / VM / Dockerfile cards. The app's containerfile tab shows only the generated text. |

---

## 4. Generate flow — ❌ (no explicit trigger) / 🔌

There is **no "Generate" button anywhere in the Deploy UI.** Generation is
implicit:

```
DeployView.task → viewModel.load() → repository.fetchDeployConfig()
   → DataStore: cli.run(["deploy","generate","--json"], cwd: projectPath)
   → JSON {terraform, ansible, containerfile} → CodeTabs
```

- The CLI handler `handleDeployGenerate` (with `--json`) reads `rawenv.toml`,
  parses it, and emits hand-rolled JSON `{"terraform":…,"ansible":…,
  "containerfile":…}` matching the Swift `DeployConfig` struct. ✅ wiring is
  shape-correct (verified by `FullE2ETests.deployGenerateJSON` /
  `FullFlowE2ETests.step14_deployGeneration`).
- ❌ **No regenerate / refresh.** `load()` runs once on appear; changing
  settings, switching providers (not possible anyway), or editing `rawenv.toml`
  does not re-trigger generation until the view is recreated.
- 🔴🔌 **Project path bug.** `DataStore.projectPath` defaults to
  `FileManager.default.currentDirectoryPath` (the *process* CWD) and is never
  set to `appState.activeProject.path`. So:
  - Selecting a different project in the sidebar does **not** change which
    `rawenv.toml` Deploy reads.
  - For a `.app` launched from Finder, CWD is typically `/`, so `rawenv.toml`
    is not found and Deploy is permanently blank regardless of the active
    project. (`RealDataRepository` is a `typealias` for `DataStore`, so the
    shipping build has the same behavior.)

### 4.1 Configured project vs unconfigured — empty state ❌

`DataStore.fetchDeployConfig()` swallows every failure and returns
`DeployConfig(terraform:"", ansible:"", containerfile:"")`:

- **Configured** (CWD has a valid `rawenv.toml` + the `rawenv` binary is found):
  JSON decodes and the three code tabs render real content. ✅
- **Unconfigured** (`rawenv.toml` missing): the CLI prints
  `Error: rawenv.toml not found … Run rawenv init first.` as **plain text** (not
  JSON) and exits non-zero. `JSONDecoder` fails → caught → **empty** config.
- **Binary missing** (`findBinary()` falls back to the literal `"rawenv"`,
  `Process.run` throws): caught → **empty** config.

In all failure cases the code tabs show an **empty `ScrollView`** — a blank
panel with no message, no error banner, and no "run `rawenv init`" call to
action. This fails the "what shows when no project configured" criterion: the
honest answer is **nothing renders**, which reads as a broken screen rather than
an empty state. `IntegrationTests.fetchDeployConfig` even documents this as
"May be empty if deploy generate fails — valid", confirming the silent-empty
contract.

---

## 5. Deploy Log tab — `DeployLogTab`

Header: "Deploy Log" + a hardcoded "Hetzner CX22" caption + a conditional
**▶ Start Deploy** button (id `deploy_start_button`), shown only when
`!isRunning && logs.isEmpty`.

### 5.1 Start deploy — 🔴 real, unconfirmed `terraform apply`

`DeployEngine.startDeploy()` → `runDeploy()` shells out, in order, to:

```
/usr/bin/env terraform init
/usr/bin/env terraform plan
/usr/bin/env terraform apply -auto-approve
```

- 🔴 **This is a real, irreversible action with no confirmation dialog.** On a
  machine with Terraform installed and valid provider credentials, a single
  click of "Start Deploy" provisions live cloud infrastructure
  (`-auto-approve`). The CLI's own `deploy apply` is deliberately gated
  ("dry-run mode … no actual deployment without `--confirm`"), but the GUI's
  `DeployEngine` **bypasses the CLI entirely** and invokes `terraform` directly,
  so the safety gate does not apply. This inconsistency is the single most
  important risk on this screen.
- In the common case (no `terraform` on PATH) `/usr/bin/env terraform` throws →
  the first log line is an error → `hasError = true`, `isRunning = false`, and
  the run stops. `DeployEngineTests.startDeploy` asserts exactly this
  (`hasError == true // terraform not installed, fails on first step`).
- Each step appends a `$ terraform …` log line; `progress` advances by 1/3 per
  successful step.

### 5.2 Progress bar — ✅

Renders only when `progress > 0`. A `GeometryReader` fills width ×
`progress`, colored `Color.error` when `hasError` else `Color.accent`. Works.

### 5.3 Log entries — ✅ (within session) / ⚠️

- Each entry is `✓`/`✗` + monospaced text, colored success/error. Native
  `ScrollView`. ✅
- The engine is the **shared `appState.deployEngine` singleton**, so logs
  persist across tab switches and across navigating away from Deploy and back
  (the View/VM are recreated but reuse the same engine). ✅
- ⚠️ **No re-run after success.** The Start button only appears when
  `logs.isEmpty`. After any run, `logs` is non-empty, so the button never
  returns. If a deploy *succeeds* (no error), there is **no way to start again**
  — no reset/clear, no "Deploy again". The only re-trigger is the error-state
  **↻ Retry** button, which exists only while `hasError`.

### 5.4 Error handling & actions — ⚠️/❌

When `hasError`, an error box appears with four buttons:

| Control | Behavior | Status |
|---|---|---|
| Error text | **Hardcoded** "⚠️ Redis failed: port 6379 already in use" — shown regardless of the actual failure (which is usually a missing-terraform error). | ⚠️ misleading |
| 🤖 AI Fix (`deploy_ai_fix`) | `applyAIFix()` appends two **canned** lines ("Applying suggested fix…", "✓ Fix applied — ready to retry"), sets `progress = 1.0`, `hasError = false`. No real diagnosis. | ⚠️ scripted |
| Change port | `Button(...) {}` — **no-op.** | ❌ stub |
| Skip | `Button(...) {}` — **no-op.** | ❌ stub |
| ↻ Retry | Calls `startDeploy()` again (re-runs the real terraform sequence). | ✅ |

After AI Fix, `hasError` is false so the box disappears and the canned lines
remain; because `logs` is now non-empty the Start button does not reappear.

### 5.5 Missing vs prototype — ❌

The prototype Deploy Log additionally has: a **Cancel** button, a **Retry All**
button, an inline **AI assistant input box**, and a richer multi-service log.
The app has **no Cancel** (the engine has no cancellation path — once
`runDeploy` starts there is no way to stop it), **no AI input**, and **no
copy/export** of the log.

---

## 6. Test coverage gaps

What exists:
- `DeployVMTests` — exercises only the **unused** 3-case VM enum
  (`load`, `defaultTab == .terraform`, `currentContentChangesWithTab`).
- `DeployEngineTests` — `initialState`, `startDeploy` (expects failure),
  `applyAIFix`, `LogEntry` identity.
- `RawenvUITests.testDeployTabSwitching` + `ComprehensiveUIE2ETests` — tab
  switching, start button, AI fix.
- CLI E2E — `deploy generate --json` shape.

Gaps (⚠️):
- **No test asserts the empty/unconfigured state** (blank panel) or that it
  *should* show a message — the silent-empty behavior is effectively
  blessed by `IntegrationTests`.
- **No test that Save / Change port / Skip are no-ops** (they pass trivially
  because they do nothing).
- **No test that the error text is hardcoded/decoupled** from the real failure.
- **No coverage of the project-path bug** (`projectPath` never tracks
  `activeProject`).
- The two `DeployTab`/`DeployViewTab` enums are never reconciled by a test.

---

## 7. Recommendations (not implemented — exploration task)

1. 🔴 Gate `Start Deploy` behind a confirmation dialog, or route it through the
   CLI's `deploy apply` (which already enforces `--confirm`). Never run
   `terraform apply -auto-approve` from a single unconfirmed click.
2. 🔴 Feed `DataStore` the **active project's path** (`appState.activeProject?.path`)
   instead of the process CWD, so Deploy reflects the selected project and works
   from a Finder-launched `.app`.
3. ❌ Add a real **empty state** to `CodeTab` when `code.isEmpty` — e.g. "No
   `rawenv.toml` found. Run `rawenv init` to generate deployment configs."
4. ❌ Implement the **Save** button (write to `terraform/` / `ansible/` /
   `Containerfile`, mirroring the CLI's non-`--json` path) and add the
   **Deploy Now / Generate / provider** controls the prototype promises, or trim
   the prototype so design and product agree.
5. ⚠️ Derive the Deploy Log **error message from the actual failed step**
   instead of the hardcoded Redis string; wire up or remove the Change port /
   Skip stubs.
6. ❌ Collapse the duplicate `DeployTab`/`DeployViewTab` enums into one source of
   truth and have the View drive `viewModel.selectedTab` (and use
   `copyCurrentContent()`), removing the dead VM code path.
7. ⚠️ Allow re-running a *successful* deploy (reset/clear log) and add a
   Cancel path to the engine.

---

## 8. Acceptance-criteria scorecard

| Criterion | Result |
|---|---|
| All 4 deploy tabs visited (terraform, ansible, containerfile, deployLog) | ✅ all present & switchable |
| Generate button exercised — produces output or shows error | ❌ no Generate button; generation is implicit on load; failures are swallowed to a blank panel |
| Code display: syntax highlighting, copy button, scroll | ⚠️ copy ✅, scroll ✅, **syntax highlighting ❌**, Save ❌ |
| Deploy log: start deploy, observe progress, handle errors | ⚠️ start/progress/retry ✅ but 🔴 real unconfirmed `terraform apply`; error text hardcoded/misleading; Change port & Skip are no-ops; no Cancel |
| Empty state: what shows when no project configured | ❌ silent blank panel, no message/error |
| All findings documented | ✅ this document |
