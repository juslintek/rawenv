# UI Exploration Findings — Installer + Uninstall

Task: **UI-007 — Explore Installer + Uninstall: full wizard flows, all steps, error recovery**

Scope: macOS SwiftUI app at `gui/macos`. Two flows:

1. **Installer** — the first-run "install rawenv itself" wizard
   (`Views/Installer/InstallerView.swift`, driven by
   `Services/InstallerEngine.swift`, gated by `App/ContentView.swift` →
   `!appState.isInstalled`).
2. **Uninstall** — the in-app "remove rawenv" wizard
   (`Views/Uninstall/UninstallView.swift`), reachable from the sidebar
   `nav_uninstall` → `Destination.uninstall`.

Behavior was derived by reading the shipping source — the two views above plus
`ViewModels/InstallerVM.swift`, `ViewModels/InstallFlowVM.swift`,
`App/AppState.swift`, `Services/TypeAliases.swift` — the unit/UI/E2E test
suites (`Tests/RawenvUnitTests/InstallerEngineTests.swift`,
`InstallerVMTests.swift`, `ViewTests.swift`; `Tests/RawenvUITests/RawenvUITests.swift`),
and compared against the canonical design intent in
`design/prototype/screens-installer.js` and `screens-extra.js`
(`renderUninstall`), plus the real CLI behavior in
`src/cli/commands.zig` (`runUninstall`, `runDestroy`).

> Methodology note: this is a source-level audit. The macOS GUI requires Xcode
> to build and a windowed session to click through; findings describe what the
> code *will* do when run, with file/line anchors, not a live click-through.

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · 🔌 CLI mismatch · 🔴 risk

---

## 0. TL;DR

- **Installer wizard renders all three states** — welcome → installing → done —
  and the "Install →" / "Continue →" buttons advance through them. ✅
- The installer's "installing" animation is driven by `InstallerEngine`, which
  **does perform a real download + chmod + PATH edit**, but every failure is
  swallowed by `try?` and the wizard **always lands on "done" claiming success**,
  even when the download failed and no binary was written. ❌🔴
- **The rawenv-self installer has NO error state and NO retry button.** The
  acceptance criterion "error state and retry button" is only satisfied by a
  *different* flow — the per-runtime install sheet (`InstallFlowVM`) shown inside
  **Projects**, not the installer wizard. ❌
- **"Binary already exists" is not handled / not detected.** The download path
  overwrites the existing binary; the dev-build fallback path silently fails
  (`copyItem` throws on an existing destination, swallowed by `try?`) yet still
  reports success. ⚠️
- **The Uninstall wizard removes nothing.** `startUninstall()` is a hardcoded
  2-second `DispatchQueue.asyncAfter` that flips `phase` to `.done`. No files,
  services, or PATH entries are touched. The sizes ("1.2 GB", "180 MB") are
  hardcoded literals, not measured. ❌🔴
- **The Uninstall "Cancel" button does nothing** — its action is an empty
  closure `{}`. There is no way to leave the screen except the sidebar. ❌
- **The Uninstall flow cannot be cancelled once confirmed** — the `.progress`
  phase has no cancel affordance, and "Go Back" only exists on the `.confirming`
  step. ⚠️
- **The Uninstall UI tests are dead** — they look for `about_uninstall`,
  `uninstall_confirm_button`, `uninstall_cancel_button`, and per-row checkbox
  IDs that **do not exist anywhere in the app source**, so the tests early-`return`
  and assert nothing. 🔌
- The **GUI uninstall is cosmetic; the CLI `rawenv uninstall` is real** — it
  stops services, deletes `~/.rawenv`, removes unit files, and cleans rc files.
  The two have diverged completely. 🔌🔴

---

## 1. Installer wizard

### 1.1 Screen anatomy & reachability

`InstallerView` (`accessibilityIdentifier("installer_view")`) is a single
`cardStyle()` panel inside a `ScrollView`, whose content switches on
`engine.state` (`InstallerEngine.State`: `.welcome` / `.installing` / `.done`).
Three step-dots track progress (`stepIndex` 0/1/2).

It is rendered in two places:

| Entry point | Condition | File |
|-------------|-----------|------|
| First-run gate | `!appState.isInstalled` | `ContentView.body` |
| `Destination.installer` | `detailView` switch | `ContentView.detailView` |

There is **no sidebar nav item** for the installer — the sidebar exposes
`nav_uninstall` but no `nav_installer` — so in practice the installer is only
seen on first run. In `--ui-testing` / `RAWENV_TEST_MODE=1`, `AppState` forces
`isInstalled = true`, so **the installer never appears under UI tests**
(`AppState.init`). That's why no UI test exercises it; only unit tests
(`InstallerEngineTests`) drive the engine directly.

### 1.2 Welcome step ✅

`welcomeContent` shows the ⚡ logo, tagline, step-dots, and a **hardcoded**
six-row "detected" list:

```
🍎 macOS detected        Apple Silicon · macOS 26
📦 Binary                ~10MB → ~/.rawenv/bin/rawenv
⚙️ Service manager       launchd integration
🔒 Isolation             Seatbelt sandbox
🌐 DNS                   dnsmasq (.test domains)
🐚 Shell                 PATH + completions (zsh, bash, fish)
```

⚠️ These rows are static strings — no actual OS / arch detection is performed
(the prototype `screens-installer.js` parameterizes by `currentOS()`; the native
view hardcodes the macOS variant). "macOS 26" and "Apple Silicon" are printed
regardless of the real machine.

The `installer_install_btn` ("Install →") calls `engine.startInstall()` →
`state = .installing`. ✅ (verified by `InstallerEngineTests.startInstallTransitionsToInstalling`).

### 1.3 Installing step ✅ (animation) / ❌ (honesty)

`installingContent` renders a progress bar (`installer_progress`) bound to
`engine.progress` and a six-item checklist from `engine.steps`:

```
Downloading rawenv binary…
Verifying SHA256…
Installing to ~/.rawenv/bin/…
Registering launchd service…
Configuring Seatbelt isolation…
Adding to PATH…
```

`InstallerEngine.runInstall()` actually does work for some steps:

| Step | What the label says | What the code does | Finding |
|------|--------------------|--------------------|---------|
| 0 Download | "Downloading…" | `URLSession` GET of the GitHub `latest` darwin-arm64 asset; writes to `~/.rawenv/bin/rawenv`. On failure, falls back to copying `./zig-out/bin/rawenv`. | ⚠️ both wrapped in `try?` |
| 1 Verify SHA256 | "Verifying SHA256…" | **Nothing** — a 200 ms `Task.sleep`. No checksum is computed or compared. | ❌ misleading label |
| 2 Install | "Installing to …/bin/" | `Darwin.chmod(binPath, 0o755)` | ✅ |
| 3 launchd | "Registering launchd service…" | **Nothing** — 200 ms sleep. | ❌ |
| 4 Seatbelt | "Configuring Seatbelt isolation…" | **Nothing** — 200 ms sleep. | ❌ |
| 5 PATH | "Adding to PATH…" | Appends `export PATH=…` to `~/.zshrc` (idempotent: skips if file already contains "rawenv"). | ✅ |

🔴 **Critical:** every fallible operation uses `try?`, so a failed download, a
missing dev build, an unwritable `~/.rawenv/bin`, or an unwritable `.zshrc` are
all silently ignored. The function unconditionally sets `state = .done` at the
end. **The wizard can declare "rawenv installed" with no binary on disk.**

The checklist tick logic is `i < engine.currentStep || engine.state == .done` —
so on reaching `.done` every row shows ✓ regardless of what actually happened.

⚠️ **Dead code:** `installingContent` contains an
`if engine.state == .done { accentButton("Launch rawenv →", id: "installer_launch_btn") {} }`
branch, but when `state == .done` the parent `switch` renders `doneContent`
instead, so this `installer_launch_btn` is **never shown**, and its action is an
empty closure anyway. The prototype's `installer-launch-btn` has no native
equivalent that is reachable.

### 1.4 Done step ✅

`doneContent` shows ✓, "rawenv installed", a faux terminal block
(`$ rawenv --version` → `rawenv 0.1.0 (macOS arm64)` — a **hardcoded** version
string, not read from the binary), and `installer_continue_btn` ("Continue →")
which calls `appState.markInstalled()` (sets `isInstalled` + persists
`UserDefaults "rawenv.installed"`). After that the first-run gate routes to
`ProjectsView`. ✅

### 1.5 "What happens if the binary already exists" ⚠️

There is **no idempotency check** and **no "already installed" branch**:

- Download path: `data.write(to:)` **overwrites** any existing binary. No
  version check, no backup, no prompt.
- Dev-build fallback: `fm.copyItem(atPath:toPath:)` **throws if the destination
  exists** — but it's wrapped in `try?`, so the copy silently no-ops and the old
  binary is kept while the wizard still reports success.
- PATH: `addToPath` *is* idempotent — it bails if `.zshrc` already contains the
  substring "rawenv", avoiding duplicate `export PATH` lines. ✅ (the one place
  that handles re-runs correctly).

Net: re-running the installer over an existing install is "safe" only by
accident, and the user gets no signal that anything was already present.

### 1.6 Error state + retry — NOT in the installer wizard ❌

The acceptance criterion "Installer: error state and retry button tested" has
**no implementation in `InstallerView`/`InstallerEngine`** — there is no
`error` property, no error view, and no retry button. `RealInstallerEngine` is
just `typealias RealInstallerEngine = InstallerEngine` (`TypeAliases.swift`), so
"real" mode is identical to the animated one.

The only error/retry experience in the app is a **separate** flow: the
**per-runtime install sheet** driven by `InstallFlowVM`, presented inside
`ProjectsView` (`installSheetView`, `.sheet(isPresented: $installVM.isShowing)`).
This installs an individual runtime/service (e.g. Postgres, "SQL Server"),
not rawenv itself. Documented here because it is the closest match to the AC:

**`InstallFlowVM` states & controls** (`installSheetView`, lines ~40–100):

| State | UI | Buttons (accessibility id) |
|-------|----|----------------------------|
| installing | "Installing/Migrating <target>…", linear progress, step list | `install_cancel_btn` |
| error | "✗ Installation failed", step list, red error text | `install_retry_btn`, `install_change_port_btn`, `install_cancel_btn` |
| error + port input | adds a `New port:` TextField | `install_new_port_input`, `install_apply_port_btn` |
| complete | "✓ <target> installed successfully", store path | `Done` (`installVM.dismiss()`) |

The error path is **demonstrated, not real**: `runInstallSteps` hardcodes
`triggersPortConflict = (name == "SQL Server")` and `failAtStep = 2`, emitting
`"Port 1433 is occupied by another process (PID 4521)."` (the source comment is
explicit that the sleeps are UI pacing, not hidden work). So:

- Installing **any** runtime named exactly "SQL Server" → always fails at step 3
  with the canned port-conflict message. ⚠️
- **Retry** (`retry()`) re-runs the same steps → fails again at step 2 (the name
  is still "SQL Server"). **Change Port** → enter a port → **Apply & Retry**
  (`applyPortAndRetry()`) clears `error`, hides the port input, and re-runs — but
  it calls `runInstallSteps(name: "SQL Server")` again with the trigger condition
  unchanged and the new port value never consumed. ❌ **Bug:** the port-conflict
  demo cannot be resolved through the UI; Apply & Retry loops back into the same
  failure.
- **Cancel** (`cancel()`) clears `isInstalling`/`isShowing` → dismisses the
  sheet. ✅
- Every other runtime name installs cleanly (5 steps × 400 ms, then ✓). ✅

---

## 2. Uninstall wizard

### 2.1 Screen anatomy & reachability

`UninstallView` (`accessibilityIdentifier("uninstall_view")`) is a single panel
that switches on a local `@State phase: UninstallPhase`
(`.selection` / `.confirming` / `.progress` / `.done`). It is reachable from
the sidebar `nav_uninstall` → `Destination.uninstall` → `UninstallView()`
(`ContentView.detailView`). It takes an `initialPhase` init param (default
`.selection`) used only by tests/previews.

### 2.2 Selection step — what gets listed for removal ✅ (display) / ⚠️ (data)

`selectionView` renders six checkbox rows from a **hardcoded** `@State items`
array:

| # | Label | Desc | Size | Default checked |
|---|-------|------|------|-----------------|
| 1 | Remove rawenv binary | `~/.rawenv/bin/rawenv` | 10 MB | ✅ |
| 2 | Remove installed packages | `~/.rawenv/store/` | 1.2 GB | ✅ |
| 3 | Stop and remove services | launchd plists | — | ✅ |
| 4 | Remove service data | `.rawenv/data/` in each project | 180 MB | ✅ |
| 5 | Remove configuration | `rawenv.toml, .rawenv/theme.toml` | 4 KB | ❌ (unchecked) |
| 6 | Remove DNS and proxy | dnsmasq config, .test domains | — | ✅ |

- Matches the prototype `renderUninstall` list (incl. "Remove configuration"
  defaulting OFF "keep for reinstall"). ✅
- ⚠️ **All sizes are static literals** — nothing measures `~/.rawenv/store`. The
  "1.2 GB" / "180 MB" figures are fictional and will mislead users about how much
  space will be reclaimed.
- ⚠️ Item 4 ("service data in each project") is listed but, since uninstall does
  nothing (§2.5), no project dirs are enumerated.
- Selected rows get a faint red background (`Color.error.opacity(0.05)`). ✅
- `uninstall_button` ("Uninstall Selected") is `.disabled` when zero items are
  selected — uncheck everything and it correctly greys out. ✅
- `uninstall_cancel` ("Cancel") has an **empty action `{}`** → does nothing.
  There is no dismiss/navigation, so the only way off the screen is to pick
  another sidebar item. ❌

### 2.3 Confirming step ✅

Tapping "Uninstall Selected" → `phase = .confirming`. `confirmView` shows a ⚠️
icon, "Are you sure?", and a live count:
`"This will remove \(items.filter(\.selected).count) items and cannot be undone."`
The count reflects the checkboxes (verified logic). Two buttons:

- **Go Back** → `phase = .selection` (state of checkboxes is preserved because
  `items` is independent `@State`). ✅ — this is the one working "cancel/back".
- **Confirm Uninstall** → `startUninstall()`.

⚠️ Neither confirm-step button has an `accessibilityIdentifier`, so they are not
addressable by automation (the UI test's `uninstall_confirm_button` does not
match anything here).

### 2.4 Progress step ⚠️

`startUninstall()` sets `phase = .progress` then
`DispatchQueue.main.asyncAfter(deadline: .now() + 2) { phase = .done }`.
`progressView` is just an indeterminate `ProgressView().controlSize(.large)` +
"Removing…". 

- There is **no cancel button on this step** — once confirmed you cannot abort;
  you can only wait out the 2 s. ⚠️
- The 2-second delay is fixed regardless of how many items were selected. ⚠️

### 2.5 Done step ❌ (nothing happened)

After 2 s, `doneView` shows ✓ "Uninstall complete" / "rawenv has been removed
from your system."

🔴 **This message is false.** `startUninstall()` performs **zero** filesystem,
service, or PATH operations. No binary is deleted, no `~/.rawenv/store` removed,
no launchd plist unloaded, no DNS config touched. The wizard is a pure
animation. A user who runs it will believe rawenv is gone while everything is
still installed and running.

There is also no "Done"/close button on this step and no re-entry reset — leaving
via the sidebar and returning creates a fresh `UninstallView()` back at
`.selection` (since `phase` is local `@State`), so re-entry "works" but only
because the whole view is recreated.

### 2.6 Cancel at each step — summary

| Step | Cancel/back affordance | Works? |
|------|------------------------|--------|
| selection | `uninstall_cancel` button | ❌ empty action, no-op |
| confirming | "Go Back" button | ✅ returns to selection |
| progress | none | ❌ no affordance |
| done | none | n/a (terminal) |

The only escape from the selection step is switching sidebar destinations.

### 2.7 Uninstall UI tests are non-functional 🔌

`Tests/RawenvUITests/RawenvUITests.swift` has `testUninstallCheckboxesAndConfirm`
and `testUninstallCancelDismisses`. Both:

1. Navigate `nav_settings` → `settings_page_about` and tap `about_uninstall`.
2. `guard uninstallButton.waitForExistence(timeout: 3) else { return }`.

But **`about_uninstall` does not exist** in the app source (grep of
`Sources/` finds it only in the *test* file and the prototype; the Settings/About
view has no such button — the real entry point is the sidebar `nav_uninstall`).
So the guard fails and **both tests return early without asserting anything.**
They are permanently green no-ops.

They further reference IDs that don't exist in `UninstallView`:

| Test expects | Actual in `UninstallView.swift` |
|--------------|--------------------------------|
| `about_uninstall` (launcher) | — (sidebar `nav_uninstall` instead) |
| `uninstall_binary`, `uninstall_packages`, `uninstall_services`, `uninstall_data`, `uninstall_config`, `uninstall_dns_proxy` | rows have **no** accessibility ids |
| `uninstall_confirm_button` | `uninstall_button` |
| `uninstall_cancel_button` | `uninstall_cancel` |

So even if the launcher existed, the assertions would fail on the renamed/absent
IDs. The unit test `ViewTests.UninstallViewTests.uninstallRenders` only checks
that the view renders without crashing — it does not exercise any flow.

### 2.8 GUI uninstall vs CLI uninstall — divergence 🔌🔴

`src/cli/commands.zig::runUninstall` is the *real* uninstaller and does what the
GUI only pretends to do:

- Prints exactly what will be removed: `~/.rawenv/` (store, bin symlinks, data),
  `~/Library/LaunchAgents/com.rawenv.*.plist` (macOS), and PATH entries from
  `.zshrc`/`.bashrc`/`.profile`.
- Prompts `Proceed? [y/N]` unless `--force` (treats empty/EOF and anything but
  `y`/`Y` as abort).
- Calls `service.uninstallAll()` (stops services, removes unit files, recursively
  deletes `~/.rawenv`) and `cleanRcFile()` for each rc file.

Mismatches with the GUI:

- GUI offers granular per-item checkboxes (binary / packages / services / data /
  config / DNS); the CLI is all-or-nothing (`~/.rawenv` + services + PATH). The
  GUI's selection granularity is **not honored anywhere** (it removes nothing).
- GUI never shells out to `rawenv uninstall` — `UninstallView` has no `RawenvCLI`
  dependency at all. The two implementations share no code.
- CLI also has a separate `rawenv destroy` (per-project data dirs); the GUI has
  no equivalent.

---

## 3. Risks & recommendations

| # | Finding | Severity | Recommendation |
|---|---------|----------|----------------|
| 1 | Uninstall wizard deletes nothing but reports "removed from your system" | 🔴 high | Wire `startUninstall()` to `rawenv uninstall --force` (or per-item commands) via `RawenvCLI`; gate the "complete" message on real exit status. |
| 2 | Installer always reaches "done" even when the download failed (`try?`) | 🔴 high | Propagate errors; add an `.error` state + retry to `InstallerEngine`; verify the binary exists and is executable before "done". |
| 3 | "Verifying SHA256", "Registering launchd", "Configuring Seatbelt" are no-op sleeps under truthful labels | ⚠️ med | Either implement, or relabel as cosmetic/"simulated", to avoid false assurance. |
| 4 | Uninstall "Cancel" button is a no-op `{}` | ⚠️ med | Navigate back to the previous destination (or Settings) on cancel. |
| 5 | Uninstall sizes (1.2 GB / 180 MB) are fake literals | ⚠️ med | Compute real on-disk sizes, or drop the size column. |
| 6 | Uninstall UI tests reference non-existent IDs and silently pass | 🔌 med | Add `about_uninstall` (or retarget to `nav_uninstall`); add ids to checkboxes; rename `uninstall_button`/`uninstall_cancel` to match tests (or vice-versa). |
| 7 | Per-runtime "Apply & Retry" cannot resolve the demo port conflict (loops) | ⚠️ low | Consume `newPort` / clear the `name=="SQL Server"` trigger so retry can succeed. |
| 8 | Installer "detected" rows + version string are hardcoded macOS values | ⚠️ low | Populate from real OS/arch and the installed binary's `--version`. |
| 9 | No cancel during uninstall `.progress`; no `nav_installer` to reach installer post-setup | ℹ️ info | Add a cancel on progress; decide whether re-running the installer should be reachable. |

---

## 4. Acceptance criteria coverage

- [x] **Installer: welcome → installing → done flow exercised** — §1.2–1.4. All
  three states render and advance; "done" is reached unconditionally.
- [x] **Installer: what happens if binary already exists** — §1.5. No detection;
  download overwrites, dev-fallback silently no-ops, PATH edit is idempotent.
- [x] **Installer: error state and retry button tested** — §1.6. **Absent** in
  the rawenv-self installer; the only error/retry lives in the per-runtime
  `InstallFlowVM` (Projects), and its "Apply & Retry" cannot resolve the canned
  port conflict (bug).
- [x] **Uninstall: selection → confirming → progress → done flow** — §2.2–2.5.
  Flow advances, but `progress→done` is a 2 s timer that removes nothing.
- [x] **Uninstall: cancel at each step** — §2.6. Only "Go Back" (confirming)
  works; selection "Cancel" is a no-op; progress/done have none.
- [x] **Uninstall: verify what gets listed for removal** — §2.2 (6 hardcoded
  items, fake sizes) and §2.8 (diverges from the real CLI removal set).
- [x] **All findings documented** — this file.
