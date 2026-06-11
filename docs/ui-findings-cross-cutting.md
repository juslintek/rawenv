# UI Exploration Findings

Task: **UI-009 — Cross-cutting: navigation, dark/light mode, window resize, accessibility**

Scope: the cross-cutting concerns of the desktop GUI — sidebar navigation between
all screens, dark/light mode rendering, window-resize/reflow behavior, and
accessibility (identifiers, screen-reader labels/roles, keyboard navigation).
The canonical/primary target is the macOS SwiftUI app (`gui/macos`), consistent
with prior UI-00x findings docs. Behavior was derived by reading the shipping
source: the navigation shell (`ContentView.swift`, `Protocols/NavigationService.swift`,
`App/AppState.swift`), the app/scene entry (`Sources/RawenvApp/main.swift`), the
theme layer (`Views/Theme.swift`, `Services/ThemeManager.swift`), every
destination view under `Views/`, and the UI-test harness
(`UITests/RawenvUITests.swift`).

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · ⌨️ keyboard gap · 🦮 screen-reader gap · 🎨 prototype-vs-impl gap

---

## 0. How navigation is wired

`Destination` (`Protocols/NavigationService.swift`) declares **10** cases:

```swift
public enum Destination: String, CaseIterable {
    case dashboard, settings, aiChat, connections, deploy, tunnel
    case menuBar, installer, projects, uninstall
}
```

`AppState` is the `NavigationService`; `currentDestination` drives the
`NavigationSplitView` detail pane (`ContentView.detailView`, which has a `case`
for **all 10** destinations). Navigation is selection-driven:

```swift
List(selection: $appState.currentDestination) { ... }
```

The sidebar (`ContentView.mainView`) renders a navigation section with **8**
tagged `Label`s, each carrying a stable a11y id:

| Sidebar label | Destination | a11y id |
|---------------|-------------|---------|
| Dashboard   | `.dashboard`   | `nav_dashboard` |
| Discovery   | `.projects`    | `nav_discovery` |
| AI Chat     | `.aiChat`      | `nav_ai_chat` |
| Connections | `.connections` | `nav_connections` |
| Deploy      | `.deploy`      | `nav_deploy` |
| Tunnel      | `.tunnel`      | `nav_tunnel` |
| Uninstall   | `.uninstall`   | `nav_uninstall` |
| Settings    | `.settings`    | `nav_settings` |

---

## 1. AC: "All 10 nav destinations reachable from sidebar" — ⚠️ 8 of 10 via sidebar

Only **8** of the 10 destinations have a sidebar entry. The remaining two are
reachable, but **not from the sidebar**:

- `.installer` — gated by first-run state. `ContentView.body` shows `InstallerView`
  when `!appState.isInstalled` (and `detailView` has a `.installer` case), but
  there is **no sidebar Label** for it. Once installed it is unreachable from the
  navigation list. ⚠️
- `.menuBar` — rendered by a **separate scene** (`MenuBarExtra` in
  `RawenvAppMain`), not by the split-view sidebar. `detailView` has a `.menuBar`
  case but nothing in the sidebar selects it. ⚠️

Also note `Discovery` maps to `.projects` (label/destination name mismatch — fine
functionally, but worth knowing when reading test ids vs enum names).

Verdict: every destination **can** be displayed, but the literal AC ("reachable
from sidebar") holds for 8/10. The first-run/menu-bar destinations are by design
reachable through other entry points. Recommend documenting this as intended, or
adding hidden/auxiliary nav rows if true 10/10 sidebar coverage is required.

Cross-check with tests: `RawenvUITests.testFullNavigationRoundTrip` exercises
exactly the 8 sidebar destinations (plus dashboard return) — confirming the
8-of-10 reality is also what the suite asserts. `installer` and `menuBar` are not
covered by the round-trip test.

### Sidebar interactive elements (beyond nav rows)

- `project_selector` Menu ✅ (id present) — switches `activeProject`.
- `sidebar_service_<name>` buttons ✅ — but every one just sets
  `currentDestination = .dashboard` (no per-service deep link). ⚠️
- `start_all_btn` / `stop_all_btn` ✅ ids — **empty closures `{}`** (no-ops). ❌
- Runtimes rows are plain `HStack`s (not buttons) — informational only.

---

## 2. AC: Dark mode + Light mode rendering on every screen — ✅ (with 2 minor risks)

### Mechanism

- `Views/Theme.swift` defines the palette with **appearance-adaptive** colors via
  `NSColor(name: nil) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) ... }`
  for `bgPrimary/bgSecondary/bgTertiary`, `textPrimary`, `textMuted`, `border`.
  These recompute per appearance, so backgrounds and text invert correctly. ✅
- `ThemeManager` exposes `mode` (`system`/`light`/`dark`) → `colorScheme`, applied
  at the root (`RootView.preferredColorScheme`) and again in
  `ContentView.body`. The Theme settings page (`theme_mode_picker`, segmented)
  switches it live and persists to `UserDefaults` (`theme.mode`). ✅
- `DashboardView` reads `@Environment(\.colorScheme)` to tune selection-highlight
  opacity (`0.1` in light vs `0.25`/`0.3` in dark) — explicit contrast tuning. ✅

### Per-screen check (source-derived)

Every screen draws text with `Color.textPrimary` / `Color.textMuted` (both
adaptive) over `Color.bgPrimary/Secondary/Tertiary` (adaptive). No view uses a
hard-coded black/white text on a hard-coded opposite background, so **no
invisible-text condition** was found in either mode across: Dashboard, Discovery
(Projects), AI Chat, Connections, Deploy, Tunnel, Uninstall, Settings (all 9
pages), Installer, MenuBar. ✅

### Risk 1 — fixed semantic accents (minor) ⚠️

`accent` (#6366F1), `success` (#34D399), `warning` (#FBBF24), `error` (#F87171)
are **fixed** (not appearance-adaptive). They are mid-tone and read acceptably on
both backgrounds, but:
- `accent` used as **small monospaced text** (e.g. proxy strings, selected tab
  text) on the light `bgPrimary` (#FAFAFC) lands near the WCAG AA 4.5:1 floor for
  small text. Borderline, not failing for most weights/sizes, but flag for a
  contrast pass.
- The Theme "Live Preview" "Warning" chip uses `.black` text on `warningColor` —
  fine for the default yellow, but a user-chosen dark warning color via the
  `ColorPicker` could invert to low contrast (no automatic foreground selection).

### Risk 2 — MenuBar uses raw SwiftUI colors (minor) ⚠️

`MenuBarView` uses `.green`/`.red`/`.gray`/`.primary`/`.secondary`/`Color.accentColor`
instead of the adaptive `Color.*` palette. These are system-adaptive too, so it
renders fine in both modes, but it is **stylistically inconsistent** with the rest
of the app (and ignores the user's custom `ThemeManager` colors).

---

## 3. AC: Window resize — no truncated content, proper reflow — ✅ (1 watch item)

Scene constraints (`Sources/RawenvApp/main.swift`):

```swift
WindowGroup { RootView(...) .frame(minWidth: 900, minHeight: 600) }
    .defaultSize(width: 1100, height: 700)
```

- `NavigationSplitView` provides the sidebar/detail reflow; sidebar floor is
  `themeManager.sidebarWidth` (default 240, user-adjustable 180–320 via the Theme
  page slider). At the 900px minimum, ≥660px remains for the detail pane. ✅
- Detail screens that can overflow vertically are wrapped in `ScrollView`
  (Connections, Tunnel, Settings detail, Deploy code/log tabs, Dashboard lists),
  so vertical growth/shrink reflows cleanly. ✅
- Uninstall is centered and capped at `maxWidth: 500` inside a flexible frame —
  stays centered on resize. ✅

**Watch item ⚠️:** `TunnelView` "Create Tunnel" is a single horizontal `HStack`
with fixed-width fields (Port 80, Provider 130, Relay 150) + `Spacer` + button.
It fits at the 900px minimum, but there is no wrap — if the sidebar is widened to
320 and the window is at minimum, the row gets tight (no `ViewThatFits`/wrapping
fallback). `ConnectionsView` connection strings use `.lineLimit(1)` and will
**truncate** long DSNs (mitigated by the Copy button, by design). Both are minor.

---

## 4. AC: Every button/control has an accessibility identifier — ⚠️ partial

`accessibilityIdentifier` is used heavily (108 occurrences across 12 view files),
and all primary navigation + flow controls are covered. However several
interactive controls are **missing identifiers**, so the AC ("every
button/control") is not fully met. Concrete gaps:

| View | Control(s) missing `accessibilityIdentifier` |
|------|----------------------------------------------|
| `Deploy/DeployView` | CodeTab **Copy**, **Save**; error actions **Change port**, **Skip**, **↻ Retry** |
| `Connections/ConnectionsView` | per-card **Copy** button |
| `AIChat/AIChatView` | proactive-banner **Apply**, **Dismiss** |
| `Uninstall/UninstallView` | confirm phase **Go Back**, **Confirm Uninstall**; done/progress have none (no controls) |
| `Settings/SettingsView` | **Reset to Defaults** has id; but Runtimes **+ Install**, the four **ColorPicker**s, and most General/Network/Cells/Deploy `TextField`s/`Toggle`s lack ids |
| `MenuBar/MenuBarView` | the custom **toggle pill** Button (per service) — also no label, see §5 |
| `ContentView` | sidebar **Start All**/**Stop** have ids but are no-ops |

Everything else (nav rows, deploy tabs, dashboard tabs, tunnel create/install,
connection mode buttons, AI input/send, settings pages, theme picker) **does**
carry a stable id. ✅ for the tested surface; ⚠️ for full coverage.

---

## 5. AC: Screen reader would make sense (labels, roles) — 🦮 gap

**There are zero `accessibilityLabel` / `accessibilityValue` / `accessibilityHint`
/ `accessibilityAddTraits` usages in the entire view layer.** `accessibilityIdentifier`
is an automation hook and is **not** announced by VoiceOver, so the screen-reader
experience relies entirely on SwiftUI's auto-derived labels from visible `Text`.
That is adequate for text buttons but breaks for icon-only / empty-label controls:

- 🦮 **MenuBar service toggle** — a `Button` whose label is a `RoundedRectangle`
  + `Circle` (custom switch) with **no text and no `accessibilityLabel`**.
  VoiceOver announces a nameless "button". Should expose label
  ("Toggle <service>") + `.isSelected`/value. ❌
- 🦮 **Empty-label form controls** — `Picker("", …)`, `TextField("", …)`,
  `SecureField("", …)`, `ColorPicker("", …)`, `Slider(…)` throughout Settings,
  and `Toggle("", isOn:)` in Uninstall, all use an empty label string. The
  describing text lives in a **sibling** `SettingRow`/`Text`, which is *not*
  programmatically associated, so VoiceOver reads "text field"/"color well"/
  "slider" with no name. Recommend `.accessibilityLabel(label)` or a non-empty
  control title. ⚠️
- 🦮 **Emoji-in-title buttons** — "▶ Start All", "⏹ Stop", "🤖 AI Fix",
  "↻ Retry", "Use Local ✓". VoiceOver reads the emoji name aloud
  ("play button…"). Prefer SF Symbols + an explicit `accessibilityLabel`. Minor.
- Roles: standard SwiftUI controls carry correct traits automatically; the only
  role problem is the custom MenuBar pill (a `Button` styled as a switch — should
  add `.accessibilityAddTraits(.isToggle)`-equivalent semantics).

Net: usable-but-degraded for VoiceOver. The icon-only MenuBar toggle is the one
hard ❌; the empty-label form fields are the broad ⚠️.

---

## 6. AC: Keyboard navigation — Tab moves focus logically — ⌨️ partial

- No `@FocusState`, `.focusable()`, `defaultFocus`, `.focusedValue`, or
  `.keyboardShortcut` anywhere in the views. There is **no explicit focus
  management and no keyboard shortcuts** (e.g. ⌘1…⌘9 for nav, ⌘, for Settings,
  ⌘W handled by AppKit). ⌨️
- The sidebar `List(selection:)` is keyboard-navigable with **arrow keys** by
  default, and selection drives the detail pane — so screen switching via keyboard
  works without Tab. ✅
- Standard controls (`TextField`, `Button`, `Picker`, `Toggle`, `Slider`) are
  Tab-focusable **only when macOS "Full Keyboard Access" is enabled** (System
  Settings ▸ Keyboard); SwiftUI/AppKit does not make non-text controls
  Tab-focusable by default otherwise. No custom tab order is defined, so order
  follows declaration order, which is top-to-bottom/leading-to-trailing and reads
  logically in each view. ✅ (order) / ⌨️ (no shortcuts, no default focus).
- `AIChatView` text input has `.onSubmit` → **Return sends** the message, and the
  Send button is correctly `.disabled` on empty input. ✅ Good keyboard ergonomics
  there; no comparable submit affordance on the Tunnel port field
  (`tunnel_port_input` requires a button click). ⚠️

Recommendations: add `.keyboardShortcut` for the 8 nav destinations and Settings;
set a `defaultFocus` for primary inputs (AI input, Tunnel port); add
`.onSubmit { createTunnel() }` to the tunnel port field.

---

## 7. Stubs / no-ops encountered while exercising the shell

These are not strictly cross-cutting but were surfaced during navigation and are
relevant to "does every screen render correctly":

- Dashboard tabs **Config / Connection / Cell / Backups** render only a centered
  placeholder `Text` (`config_tab`, `connection_tab`, `cell_tab`, `backups_tab`). ❌
- Sidebar **Start All / Stop** = empty closures. ❌
- Deploy **Save**, **Change port**, **Skip** = empty closures; AI-banner
  **Dismiss**, Uninstall selection **Cancel** = empty closures. ❌
- Settings **Services** page is a one-line redirect message; **+ Install**
  (Runtimes) is a no-op. ❌
All render without layout errors in both color schemes; they are functional stubs.

---

## 8. Cross-platform parity note

Findings above are for `gui/macos` (SwiftUI). The Linux (Vala/GTK, `gui/linux`)
and Windows (WinUI/XAML, `gui/windows`) ports were not re-audited here; GTK
exposes accessibility via ATK and WinUI via UIA, and both have their own
theme/resize stories. A parity audit of those two ports against §1–§6 is
recommended as a follow-up if cross-platform a11y is in scope.

---

## 9. Summary scorecard

| Acceptance criterion | Result |
|----------------------|--------|
| All 10 nav destinations reachable from sidebar | ⚠️ 8/10 from sidebar; `installer` (first-run) + `menuBar` (separate scene) reachable elsewhere |
| Dark mode: every screen, no invisible text/contrast | ✅ (adaptive palette); ⚠️ 2 minor: fixed accent small-text contrast, MenuBar uses raw colors |
| Light mode: every screen | ✅ |
| Window resize: no truncated content, reflow | ✅; ⚠️ Tunnel create-row doesn't wrap, Connections DSN `lineLimit(1)` truncates by design |
| Every button/control has an a11y identifier | ⚠️ partial — ~10 controls missing ids (§4) |
| Screen reader makes sense (labels/roles) | 🦮 gap — 0 `accessibilityLabel`s; MenuBar toggle is nameless (❌); empty-label form fields (⚠️) |
| Keyboard: Tab moves focus logically | ⌨️ partial — arrow-key sidebar nav ✅, declaration order ✅, but no shortcuts/default focus; Tab needs Full Keyboard Access |
| All findings documented | ✅ (this document) |

### Highest-value fixes (prioritized)
1. **MenuBar toggle** — add `accessibilityLabel` + toggle semantics + identifier (hard a11y failure). 
2. **Empty-label form controls** — associate the visible `SettingRow` label via `.accessibilityLabel(...)` across Settings + Uninstall.
3. **Missing identifiers** — add ids to the ~10 controls in §4 to satisfy "every control" and to make them testable.
4. **Keyboard** — `.keyboardShortcut` for nav + Settings; `.onSubmit`/`defaultFocus` for Tunnel port.
5. **Nav coverage** — decide whether `installer`/`menuBar` need sidebar entries or are intentionally out-of-band (document either way).
6. **Contrast** — verify fixed `accent` small-text against light `bgPrimary`; auto-pick foreground for user-chosen semantic colors.
