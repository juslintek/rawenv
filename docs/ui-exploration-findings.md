# UI Exploration Findings

Task: **UI-001 — Explore Dashboard: all tabs (logs, config, connection), all states, all controls**

Scope: macOS SwiftUI app at `gui/macos` (`DashboardView` + `DashboardViewModel`),
the screen reached via the sidebar **Dashboard** destination. Behavior was
derived by reading the shipping source, the data layer (`DataStore`), the unit
test doubles (`TestDataRepository`), and comparing against the interactive
design intent in `design/prototype/screens-gui.js` (the canonical "what it
SHOULD do").

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · 🔌 CLI mismatch

---

## 1. Screen anatomy

`DashboardView` (`Sources/Rawenv/Views/Dashboard/DashboardView.swift`) is a
vertical stack:

1. **Stats cards row** — CPU / Memory / Running (`StatsCard` x3).
2. **Service list** — selectable `List` of `viewModel.services`.
3. **Tab bar** — pill buttons generated from `DashboardTab.allCases`.
4. **Tab content** — switched on `viewModel.selectedTab`.

The sidebar (`ContentView.mainView`) that frames this screen also carries the
**Start All / Stop** buttons, the project selector, and the service/runtime
lists — these are exercised here because they are part of the dashboard
experience even though they live in `ContentView`.

### Tab inventory — finding ❌/⚠️

The task names **3 tabs** (logs, config, connection). The implementation
actually defines **5**:

```swift
public enum DashboardTab: String, CaseIterable {
    case logs, config, connection, cell, backups
}
```

So `cell` and `backups` are present in the UI tab bar but were not in the task
scope and are also unimplemented (see §5). The tab bar renders all five pills
unconditionally.

---

## 2. Logs tab (`.logs`) — default tab

What it does:
- ✅ Renders `List(viewModel.logs)`; each row = monospaced `time` + `msg`,
  colored by `level` (`warn`→warning, `error`→error, else `textPrimary`).
- ✅ Native `List` scrolling works (vertical).

What it does **not** do vs. acceptance criteria ("verify log content updates,
scroll, filter"):
- ❌ **No log updates / no live tail.** Logs are loaded once in
  `.task { await viewModel.load() }`. There is no timer, no refresh button, no
  `onReceive`/polling. New log lines never appear until the view is recreated.
- ❌ **No filter control** (no search field, no level filter, no per-service
  filter).
- ❌ **No auto-scroll-to-bottom** and no "jump to latest" affordance.
- ⚠️ **Selecting a service does nothing to the logs.** The service `List` binds
  `viewModel.selectedService`, but logs are global — `fetchLogs()` reads the
  newest file in `~/.rawenv/logs` and is never re-queried per service. The
  selection only changes row highlight color.

vs. prototype (`screens-gui.js`, `t===0`): the design shows the log viewer
**plus a connection bar** with a copy button pinned at the bottom of the logs
tab. The Swift logs tab has no connection bar.

🔌 CLI mismatch: `DataStore.fetchLogs()` parses raw files in `~/.rawenv/logs`
(last file, last 50 lines, `prefix(8)` as time). It does **not** call any
`rawenv` CLI command, and the level is inferred by substring match on
`ERROR`/`WARN`. There is no `rawenv logs` subcommand backing this, so log
formatting depends entirely on whatever wrote those files.

---

## 3. Config tab (`.config`) — ❌ STUB

```swift
case .config:
    Text("Configuration")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("config_tab")
```

- ❌ **No config display.** Just a centered literal string "Configuration".
- ❌ **No edit mode**, no inputs, no "Edit Raw File", no "Full Editor".
- ❌ **No reset / no save.**

This fails every part of the acceptance criterion "verify config display, edit
mode if available, reset" — none of those controls exist.

vs. prototype (`t===1`): the design specifies a full per-service config editor:
`port`, `max_connections`, `shared_buffers`, `work_mem`,
`effective_cache_size`, `log_destination`, `data_directory`, each with an
editable `<input>`, plus **Full Editor**, **Edit Raw File**, **Save & Restart**,
and **Reset to defaults** buttons. The Swift implementation ships none of it.

---

## 4. Connection tab (`.connection`) — ❌ STUB (functionality lives elsewhere)

```swift
case .connection:
    Text("Connection Info")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("connection_tab")
```

- ❌ **No connection strings shown.**
- ❌ **No copy buttons.**

This fails the acceptance criterion "verify connection strings shown, copy
buttons work" — there are none on the dashboard.

**Important inconsistency:** the real connection UI (connection string + working
**Copy** button + Use Remote/Use Local/Proxy mode toggles) exists, but in a
**separate top-level navigation destination** — `ConnectionsView`
(`Views/Connections/ConnectionsView.swift`, sidebar item "Connections",
`nav_connections`). So the dashboard's "connection" tab is a dead stub while a
parallel, fully working Connection Manager lives one nav level away. A user
clicking the dashboard's Connection tab gets a blank label and no hint that the
functionality is under "Connections" in the sidebar.

`ConnectionsView` behavior (verified by reading source, for completeness):
- ✅ Copy button copies `activeConnectionString` to `NSPasteboard`, flips label
  to "Copied!" for 1.5s (`connectionsCopyToClipboard` unit test covers this).
- ✅ Mode toggles (`remote`/`local`/`proxy`) switch the active string and badge.

vs. prototype (`t===2`): the design's connection tab is far richer — connection
string + Copy, env var, host, port, DNS alias, unix socket, "Create tunnel"
button, and a "Quick test" terminal block. None of this is on the dashboard;
`ConnectionsView` implements a subset (string, copy, modes) but not host/port/
DNS/socket/tunnel rows.

🔌 CLI mismatch: `DataStore.fetchConnections()` shells `rawenv connections
--json` expecting `{from,to}` pairs, then hardcodes `local: "localhost"`,
`mode: "local"`, `badge: "Local"`, and leaves `proxy`/`alternative` nil. So the
proxy mode toggle in `ConnectionsView` can never show a real proxy string from
the CLI (it falls back to `original`), and the DNS alias / unix socket the
prototype promises are not produced by the CLI at all.

---

## 5. Cell tab (`.cell`) and Backups tab (`.backups`) — ❌ STUBS (out of task scope but present)

Both are single centered labels:
```swift
case .cell:    Text("Cell Isolation")    // accessibilityIdentifier("cell_tab")
case .backups: Text("Backups")           // accessibilityIdentifier("backups_tab")
```
No controls. Documented here because they appear in the live tab bar and a user
will click them. The prototype (`t===3`) specifies a rich Cell isolation panel
(mechanism, filesystem/network scope, editable memory/CPU limits, PID, live
usage, "View sandbox profile"). None implemented.

---

## 6. Stats cards row — ⚠️ misleading in real usage

- ✅ "Running" card shows `runningCount/total` correctly.
- ✅ `totalCPU` sums each service's `cpu` (strips `%`); `totalMem` sums `mem`
  (strips both `" MB"` and `"MB"`). With the test data
  (`84MB`+`12MB`, `2.1%`+`0.3%`) this yields `2 %` and `96 MB`.
- 🔌 **CPU/Memory are effectively always 0 in production.**
  `DataStore.fetchServices()` maps `rawenv services ls --json`
  (`{name,version,status,port}`) into `Service(... cpu: nil, mem: nil, ...)`.
  The CLI provides **no** cpu/mem/pid/uptime. So in the shipping app the CPU
  card shows `0%` and Memory shows `0 MB` regardless of actual usage. The
  non-zero values only appear with `TestDataRepository` in unit tests. This is
  the clearest displayed-data-vs-CLI-output inconsistency.
- ⚠️ Stats are a one-shot snapshot (loaded in `.task`), never refreshed.

---

## 7. Service list & selection — ⚠️

- ✅ Lists services with icon, name, `v{version} • port {port}`, optional
  cpu/mem, `StatusDot`, status text. Selected row highlights via
  `listRowBackground` + accent text.
- ✅ `selectedService` defaults to `services.first` after `load()`
  (verified: `PostgreSQL` in tests).
- ⚠️ **Selection is cosmetic only.** Selecting a service does not drive any tab
  (logs are global, config/connection/cell/backups are stubs). In the prototype
  every tab is keyed off `window._selectedSvc`; here selection has no functional
  consequence.

---

## 8. Sidebar controls framing the dashboard (`ContentView`) — ⚠️/❌

- ❌ **Start All button** (`start_all_btn`) has an **empty action**:
  `Button("▶ Start All") {}`. Clicking does nothing.
- ❌ **Stop button** (`stop_all_btn`) likewise: `Button("⏹ Stop") {}`. No-op.
  These are the most visible dead controls on the dashboard screen — they look
  actionable but are wired to empty closures.
- ⚠️ **Sidebar service rows** (`sidebar_service_*`) set
  `currentDestination = .dashboard` but do **not** select that service in the
  `DashboardViewModel`. Each navigation to `.dashboard` builds a **fresh**
  `DashboardViewModel(repository:)` in `ContentView.detailView`, so any
  selection/tab state is discarded on every navigation (no state persistence).
- ✅ Project selector menu (`project_selector`) switches `appState.activeProject`.

---

## 9. State matrix: mock data loaded vs empty

Exercised at the ViewModel level (see `DashboardExplorationTests.swift`).

| State | services | logs | selectedService | Stats cards | Lists |
|-------|----------|------|-----------------|-------------|-------|
| **Loaded** (`TestDataRepository`) | 3 (2 running, 1 stopped) | ≥1 | `PostgreSQL` | CPU 2%, Mem 96 MB, Running 2/3 | populated |
| **Empty** (`EmptyDataRepository`) | 0 | 0 | `nil` | CPU 0%, Mem 0 MB, Running 0/0 | blank |
| **Production** (`DataStore`+CLI) | from `services ls` | from `~/.rawenv/logs` | first | CPU 0%, Mem 0 MB (CLI has no metrics) | populated, no metrics |

- ❌ **No empty-state placeholder.** With zero services/logs the lists render
  completely blank — no "No services configured" / "No logs yet" message. The
  `Running 0/0` card and empty lists give no guidance.
- ✅ No crash / no force-unwrap on empty data (`services.first` → nil is safe).

---

## 10. Accessibility identifiers (good)

Every interactive surface is labeled, which makes UI automation feasible:
`dashboard_view`, `dashboard_services_list`, `service_<name>`,
`tab_logs|config|connection|cell|backups`, `logs_list`, `config_tab`,
`connection_tab`, `cell_tab`, `backups_tab`, plus sidebar
`start_all_btn`, `stop_all_btn`, `sidebar_service_<name>`, `nav_*`.

---

## 11. Summary of defects (prioritized)

| # | Severity | Finding |
|---|----------|---------|
| 1 | High | **Start All / Stop buttons are no-ops** (empty closures) — primary dashboard action does nothing. |
| 2 | High | **Config tab is a stub** — no display/edit/reset; prototype specifies a full editor. |
| 3 | High | **Connection tab is a stub** — no strings/copy; real Connection Manager is hidden in a separate `Connections` sidebar destination. |
| 4 | High | **CPU/Memory cards always 0 in production** — CLI `services ls` supplies no metrics; non-zero only under test doubles. |
| 5 | Med | **Logs never update** — load-once, no tail/refresh/filter. |
| 6 | Med | **Service selection is cosmetic** — does not drive any tab. |
| 7 | Med | **Cell & Backups tabs are stubs** present in the live tab bar. |
| 8 | Med | **No empty-state messaging** — blank lists with zero data. |
| 9 | Low | **Dashboard VM rebuilt on every navigation** — selection/tab state not persisted. |
| 10 | Low | Logs are file-scraped (`~/.rawenv/logs`) with no backing CLI command; level inferred by substring. |

## 12. Recommendations

- Wire `start_all_btn` / `stop_all_btn` to `ServiceManager`/`ServiceBackend`
  (the backend already supports `start`/`stop`/`list`).
- Implement the config and connection tabs (or, at minimum, make the dashboard
  Connection tab redirect/link to `ConnectionsView` so it is not a dead end).
- Either hide `cell`/`backups` pills until implemented, or build the panels.
- Add per-service log filtering and a refresh/tail mechanism.
- Surface cpu/mem from the CLI (extend `services ls --json`) or drop the cards
  in production to avoid a permanently-zero readout.
- Add empty-state placeholders for the service and log lists.

---

## Verification

- `swift test` (in `gui/macos`): **472 tests, 83 suites — all pass** (baseline),
  including the new `DashboardExplorationTests` suite added to back up §2, §7,
  and §9 findings (tab reachability, empty-state, no-op selection).
