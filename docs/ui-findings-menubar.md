# UI Exploration Findings

Task: **UI-008 — Explore MenuBar: status item, dropdown, quick actions**

Scope: the **menu bar status item** surface of rawenv. There are **three distinct
implementations** of this concept, and they do **not** agree on behavior:

1. **macOS SwiftUI `MenuBarExtra`** — the rich popover panel
   (`gui/macos`, `MenuBarView.swift` + `RawenvApp` `main.swift`). This is the
   canonical/primary target, consistent with prior UI-00x findings docs.
2. **Native Zig CLI `rawenv menubar`** — an `NSStatusItem`/`NSMenu` built
   directly against the ObjC runtime (`src/platform/macos.zig::runMenuBar`,
   dispatched from `src/cli/commands.zig::runMenubar`).
3. **Zig raylib GUI menu-bar screen** — a model-only popover stub
   (`src/gui/screens/menubar.zig`), **not wired into the render loop**.

Behavior was derived by reading the shipping source for all three, the data layer
(`ServiceManager`, `AppState`, `DataStore`), the SwiftUI unit/UI tests
(`MenuBarViewTests`, `RawenvUITests` menu-bar suite), and comparing against the
canonical design intent in the interactive prototype
(`design/prototype/screens-gui.js::renderMenuBar`).

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · 🔌 CLI/data mismatch · 🎨 prototype-vs-impl gap · 🧪 test-vs-impl gap

---

## 0. How the menu bar is reached

### 0.1 SwiftUI `MenuBarExtra` (primary)

`Sources/RawenvApp/main.swift`:

```swift
MenuBarExtra("rawenv", image: "MenuBarIcon") {
    MenuBarView()
        .environmentObject(appState)
        .environmentObject(appState.themeManager)
}
.menuBarExtraStyle(.window)
```

- ✅ The status item is registered at app launch via SwiftUI's `MenuBarExtra`
  scene, alongside the main `WindowGroup`. Icon is the asset `MenuBarIcon`
  (`Assets.xcassets/MenuBarIcon.imageset`).
- ✅ `.menuBarExtraStyle(.window)` renders `MenuBarView` as a popover **window**
  (a fixed `width: 300` panel), which is why the view is a full SwiftUI layout
  rather than a list of `NSMenuItem`s.
- ⚠️ The popover gets its **own** `appState` injected — the same `@StateObject`
  shared with the main window — so toggling a service from the menu bar mutates
  the same `serviceManager` the main window observes. Good. But `appState.navigate(to:)`
  from the popover (Dashboard button) only changes `currentDestination`; it does
  **not** raise/focus the main window (see §3.3).

### 0.2 In-window `.menuBar` destination — 🧪 effectively unreachable

`Destination` (`Protocols/NavigationService.swift`) includes `case menuBar`, and
`ContentView.detailView` has a `case .menuBar: MenuBarView()` arm. **However**,
the `ContentView` sidebar `List` has **no nav row tagged `.menuBar`** (rows exist
for dashboard, projects, aiChat, connections, deploy, tunnel, uninstall, settings
only). So inside the main window the menu-bar panel can only be shown by
programmatically setting `currentDestination = .menuBar` — which only the unit
test `contentViewMainMenuBar()` does. No user-facing navigation reaches it.

### 0.3 Native CLI `rawenv menubar`

`README` lists `rawenv menubar` ("Launch the macOS menu bar status item").
`commands.runMenubar` calls `macos.runMenuBar` on macOS, else prints
`"Menu bar is only available on macOS."` and returns `ExitCode.user`. This is a
**separate, simpler** NSStatusItem (see §5) and shares **no code** with the
SwiftUI `MenuBarView`.

---

## 1. SwiftUI `MenuBarView` — anatomy

`Views/MenuBar/MenuBarView.swift`, root id `menubar_view`, fixed `width: 300`:

1. **Header** — `⚡ rawenv` (bold) + right-aligned `"<running>/<total> running"`.
2. **Project row** — active project name + a `▾` chevron glyph.
3. Divider.
4. **Service list** — `ForEach(appState.serviceManager.services)`; each row:
   - status dot (green if `running`, else red),
   - `service.name`,
   - `:<port> · <mem> · <uptime>` when running, else `:<port> · stopped`,
   - a **custom toggle pill** (RoundedRectangle + offset Circle) that calls
     `startService`/`stopService`. Row id `menubar_service_<name>`.
5. Divider.
6. **Actions** — `▶ Start All` (id `menubar_start_all`) and `Dashboard`
   (id `menubar_open_dashboard`).
7. Divider.
8. **Footer** — `rawenv v0.2.0 · <project name | "no project">`.

---

## 2. Acceptance-criteria results (SwiftUI, primary)

### AC: "Menu bar icon/status indicator shown" — ✅ (status indicator misleading)

- ✅ Status item registered via `MenuBarExtra` with the `MenuBarIcon` asset.
- ✅ Header shows a live `runningCount/total` summary computed from
  `serviceManager.services.filter { $0.status == "running" }`.
- ⚠️ The count is **always colored green** (`.foregroundStyle(.green)`), even when
  `0/N` are running. A "0/5 running" in green is misleading; the prototype uses
  `--success` too, so this is a faithful port of a prototype quirk (🎨), but it
  is still a status-color bug worth fixing.

### AC: "Dropdown: service list with status" — ✅

- ✅ Each service renders a colored dot, name, port, and either
  `mem · uptime` (running) or `stopped`. Empty/`nil` `mem`/`uptime` degrade to a
  dangling `" · "` separator (cosmetic — see §4.2).
- ✅ List is driven by the shared `ServiceManager.services`, which prefers live
  CLI data (`backend.list()`) and falls back to `repository.fetchServices()`.

### AC: "Quick actions: start/stop individual services" — ⚠️ works, but a11y/test gaps

- ✅ Functionally: tapping a row's pill calls `stopService(name:)` when running
  or `startService(name:)` when stopped; both dispatch to the
  `LaunchctlServiceBackend` then `refresh()` from the authoritative CLI list.
- ⚠️ The pill is a plain `Button` wrapping shapes — **not** a SwiftUI `Toggle`,
  and it carries **no `accessibilityIdentifier`**. The row container has
  `menubar_service_<name>` but the interactive control itself is unlabeled.
- 🧪 `RawenvUITests.testMenuBarServiceToggle` looks for
  `app.switches.matching(identifier: "menubar_service_toggle")`. That identifier
  **does not exist** and the control is not an accessibility *switch*, so the
  matcher never resolves. The test only acts `if toggle.waitForExistence(...)`,
  so it **silently no-ops** and passes without asserting anything.

### AC: "Project switching from menu bar" — ❌ NOT met

- ❌ The project row is a static `HStack { Text(name); Text("▾") }`. The `▾`
  chevron **implies a dropdown** but there is **no `Menu`** and **no tap target**.
  You cannot switch projects from the menu bar.
- 🎨 The prototype `renderMenuBar` is identical (decorative `▾`, no handler), so
  the impl faithfully reproduces a non-functional affordance.
- 🔁 Contrast with `ContentView`'s sidebar, which *does* have a real project
  `Menu` (id `project_selector`) iterating `appState.managedProjects`. The menu
  bar deliberately omits it. If project switching is a requirement here, it needs
  to be added (the data — `managedProjects` + `activeProject` setter — already
  exists on `AppState`).

### AC: "Empty state: no project configured" — ⚠️ inconsistent fallbacks

When `appState.activeProject == nil`:

- ⚠️ The **project row** falls back to the literal string `"my-app"`
  (`appState.activeProject?.name ?? "my-app"`) — it pretends a sample project
  exists.
- The **footer** falls back to `"no project"` (`?? "no project"`).
- So the same empty state shows **"my-app"** at the top and **"no project"** at
  the bottom simultaneously. The header still shows `0/<count> running`.
- The unit test `menuBarNoProject()` sets `activeProject = nil` and only verifies
  the view *renders* (no crash); it does not assert the displayed copy, so the
  inconsistency is untested. Recommend a single, honest empty-state label
  (e.g. "No project").

---

## 3. SwiftUI — other observations

### 3.1 Start All — ✅

`▶ Start All` calls `serviceManager.startAll()`, which iterates services where
`status != "running"` and starts each. (The prototype's Start All button has no
handler — 🎨 impl is *better* than prototype here.)

### 3.2 Running-count helper — ✅

`runningCount` recomputes on every body eval from `services`. Because
`ServiceManager` is `@Published`, the header and dots update reactively after a
toggle settles.

### 3.3 Dashboard button — ⚠️ no window activation

`menubar_open_dashboard` calls `appState.navigate(to: .dashboard)`. This sets
`currentDestination` but does **not** call `NSApp.activate(...)` or order the main
window front. If the main window is hidden/minimized, tapping "Dashboard" appears
to do nothing visible. (The native CLI menu has the same class of issue — its
"Open GUI"/"Open TUI" items have `action == null`; see §5.)

### 3.4 Version string drift — 🎨

Footer hardcodes `v0.2.0`; prototype footer says `v0.1.0` and also shows a total
memory figure (`· 462MB`) that the impl drops. `README`/`--version` report
`0.2.0`, so the impl string is currently correct but hardcoded (will drift again
on the next bump).

---

## 4. SwiftUI — cosmetic / robustness nits

### 4.1 Toggle pill is custom — re-skin risk
The pill manually animates a `Circle().offset(x: isOn ? 8 : -8)`. It ignores the
system accent / `ThemeManager.accentColor` and uses a hardcoded `Color.green`,
so it won't follow a custom theme the way the rest of the app does.

### 4.2 Dangling separator on missing metrics
`":\(port) · \(isOn ? "\(mem ?? "") · \(uptime ?? "")" : "stopped")"` produces
`":5432 ·  · "` when a running service reports `nil`/empty `mem` and `uptime`.
Guard the interpolation or join non-empty components.

---

## 5. Native CLI `rawenv menubar` (`src/platform/macos.zig`) — ⚠️/❌

A completely separate `NSStatusItem` built via the ObjC runtime. It parses
`rawenv.toml` from CWD for `[services.*]` `version` keys and builds an `NSMenu`:

| Menu item | Behavior | Verdict |
|-----------|----------|---------|
| Status title `⚡` | Set as item title | ✅ icon shown |
| Header `rawenv — 0/{N} running` | **`0` is hardcoded** in the format string | 🔌 always reports 0 running, regardless of actual state |
| Service rows `● {name} v{version}` | `action = null`, **same `●` for every service** | ⚠️ no real status; non-interactive (no start/stop) |
| `Open TUI` / `Open GUI` | `action = null` | ❌ non-functional placeholders |
| `Quit` (⌘Q) | `action = terminate:` | ✅ works |

Findings:
- 🔌 **Header is a lie**: `bufPrintZ(&header_buf, "rawenv — 0/{d} running", .{total})`
  — the numerator is the literal `0`, never the live running count.
- ⚠️ **No status differentiation**: every service is prefixed with `●` (no
  running/stopped color or glyph); status is never read.
- ❌ **No quick actions**: service rows and the Open-TUI/Open-GUI items have
  `action == null`, so they are inert.
- ❌ **No project switching**: there is no project concept here at all — it only
  knows the CWD's `rawenv.toml`.
- ⚠️ **Empty `rawenv.toml`**: with no `[services.*]` entries the menu shows
  `rawenv — 0/0 running`, no service rows, then the inert Open/Quit block — an
  acceptable (if bare) empty state, but it's the *only* honest "0" in the file
  and it's honest only by coincidence.

This native path is best described as a **proof-of-concept stub**. The SwiftUI
`MenuBarExtra` is the real, feature-complete menu bar.

---

## 6. Zig raylib GUI menu-bar screen (`src/gui/screens/menubar.zig`) — ❌ not wired

A `MenuBarState` model with `visible`, `services`, `show/hide/toggleVisibility`,
`runningCount()`, and `statusSummary()` ("All services running" / "All services
stopped" / "Some services running"). It has unit tests for visibility and
summary. **But** `src/gui/app.zig` only references it as `_ = menubar;` inside a
`test {}` block — there is **no render call** in the raylib draw loop. So:

- ❌ Nothing draws this screen in the raylib GUI; it is model-only.
- ✅ Its model logic (`runningCount`, `statusSummary`) is the *correct* logic the
  native CLI header (§5) should have used but doesn't — note the duplication and
  the missed reuse.

---

## 7. Cross-implementation summary

| Capability | SwiftUI `MenuBarExtra` | Native CLI `rawenv menubar` | raylib screen |
|------------|------------------------|------------------------------|---------------|
| Status icon shown | ✅ `MenuBarIcon` | ✅ `⚡` title | ❌ not rendered |
| Live running count | ✅ (always green) | 🔌 hardcoded `0/N` | ✅ model only |
| Service list w/ status | ✅ dot + metrics | ⚠️ `●` only, no status | ✅ model only |
| Start/stop individual | ✅ (no a11y id) | ❌ inert | ❌ |
| Start All | ✅ | ❌ | ❌ |
| Project switching | ❌ decorative `▾` | ❌ no project concept | ❌ |
| Empty state | ⚠️ "my-app" vs "no project" | ⚠️ bare `0/0` | n/a |
| Open Dashboard/GUI | ⚠️ no window raise | ❌ inert | ❌ |

---

## 8. Recommendations (priority order)

1. **Fix the native CLI header** (`macos.zig`): compute the real running count
   instead of the hardcoded `0` (reuse `menubar.zig::runningCount`/`statusSummary`
   logic), or document the CLI status item as deprecated in favor of the app.
2. **Implement project switching** in `MenuBarView` — replace the static project
   row with a `Menu` over `appState.managedProjects` setting `activeProject`,
   mirroring `ContentView`'s `project_selector`. This is the only **unmet** AC.
3. **Unify the empty state** — one honest label ("No project") in both the
   project row and footer; drop the `"my-app"` fallback.
4. **Make the toggle accessible** — give the pill `accessibilityIdentifier(
   "menubar_service_toggle")` and `.accessibilityAddTraits(.isButton)` (or use a
   real `Toggle`), so `RawenvUITests.testMenuBarServiceToggle` actually exercises it.
5. **Reconcile test↔impl identifiers** — `RawenvUITests` references
   `menubar_popover`, `menubar_running_count`, `menubar_service_list`,
   `menubar_service_toggle`; the view exposes `menubar_view`,
   `menubar_service_<name>`, `menubar_start_all`, `menubar_open_dashboard`. Either
   add the missing ids or fix the tests; right now the menu-bar UI tests pass
   without asserting anything.
6. **Activate the window** on Dashboard tap (`NSApp.activate(ignoringOtherApps:true)`
   + order front), and wire the native CLI "Open GUI"/"Open TUI" items.
7. **Color/robustness**: don't render the running count green at `0`; guard the
   `mem`/`uptime` interpolation against the dangling `" · "`.

---

## 9. Verification notes

Docs-only exploration task — no source was modified, so language typecheck/lint
is not applicable. Findings were cross-checked against the shipping sources cited
inline and the SwiftUI test suites; the test↔impl identifier gaps in §2 and §8.5
were confirmed by reading both `MenuBarView.swift` and `RawenvUITests.swift`.
