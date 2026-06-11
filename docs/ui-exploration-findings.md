# rawenv UI Exploration — Definitive Findings & Improvement Backlog

This is the consolidated, definitive report compiled from the full UI exploration
(UI-001 through UI-010). It merges the individual exploration documents into one
backlog, grouped by screen, with every finding categorized by severity and a
clear **HOW IT SHOULD BE** description of the ideal behavior.

Primary target: the macOS SwiftUI app (`gui/macos`), with native CLI (`rawenv`)
and raylib GUI noted where relevant. Behavior was derived from reading shipping
source, data layers, tests, and the canonical design intent in
`design/prototype/*`.

Source documents consolidated here:

| Area | Source doc | Task |
|------|-----------|------|
| Dashboard | `ui-exploration-findings.md` (this file, original) | UI-001 |
| Projects / Discovery | `ui-findings-projects.md` | UI-002 |
| AI Chat | `ui-findings-ai-chat.md` | UI-003 |
| Deploy | `ui-findings-deploy.md` | UI-004 |
| Connections & Tunnel | `ui-findings-connections-tunnel.md` | UI-005 |
| Menu Bar | `ui-findings-menubar.md` | UI-006 |
| Settings | `ui-settings-exploration.md` | UI-007 |
| Installer & Uninstall | `ui-findings-installer-uninstall.md` | UI-008 |
| Cross-Cutting (nav/theme/resize/a11y) | `ui-findings-cross-cutting.md` | UI-009 |
| State Handling (empty/loading/error) | `ui-findings-state-combinations.md` | UI-010 |

---

## Severity definitions

| Severity | Meaning |
|----------|---------|
| **broken** | The control/feature exists but does nothing, crashes, errors, or loops. A user who interacts with it gets no result or a wrong result. |
| **wrong** | It works, but produces incorrect, misleading, or unsafe behavior/data (e.g. hardcoded values, fake labels, decoupled state). |
| **missing** | A feature or control that should exist per design/prototype/AC does not exist at all. |
| **polish** | Works correctly but could be improved (cosmetic, consistency, ergonomics, robustness). |

Findings within each screen section are sorted by severity: **broken → wrong → missing → polish**.

---

## Summary table — findings by severity per screen

| Screen | broken | wrong | missing | polish | Total |
|--------|:------:|:-----:|:-------:|:------:|:-----:|
| Dashboard | 1 | 3 | 5 | 1 | 10 |
| Projects / Discovery | 10 | 4 | 6 | 1 | 21 |
| AI Chat | 2 | 1 | 1 | 3 | 7 |
| Connections & Tunnel | 3 | 5 | 9 | 0 | 17 |
| Deploy | 4 | 4 | 9 | 1 | 18 |
| Menu Bar | 3 | 5 | 3 | 4 | 15 |
| Settings | 7 | 10 | 3 | 1 | 21 |
| Installer & Uninstall | 6 | 7 | 7 | 0 | 20 |
| State Handling (cross-screen) | 1 | 7 | 15 | 1 | 24 |
| Cross-Cutting (nav/theme/a11y) | 0 | 1 | 4 | 6 | 11 |
| **TOTAL** | **37** | **47** | **62** | **18** | **164** |

> Note: The **State Handling** and **Cross-Cutting** sections deliberately overlap
> with per-screen sections where a defect is best understood as a systemic
> pattern (e.g. the non-throwing repository that collapses every error into an
> empty state). Cross-references are noted inline.

### Highest-priority themes (read first)

1. **Dangerous, unconfirmed `terraform apply -auto-approve`** from the Deploy
   screen (Deploy D-1) — the single biggest risk in the app.
2. **Primary action buttons are no-ops** — Dashboard Start All/Stop, Settings
   save, many Projects scan/add buttons, Uninstall actually removes nothing.
3. **Settings persist nothing** — every edit is lost on re-render (Settings S-1).
4. **Errors are invisible** — the data layer swallows every failure into an empty
   state, so users can't tell "broken" from "empty" (State Handling ST-1).
5. **Production data is fake/zero** — CPU/Memory always 0, hardcoded versions,
   hardcoded sizes, hardcoded error text.

---

## 1. Dashboard

`DashboardView` + `DashboardViewModel`, reached via sidebar **Dashboard**. Frame
controls (Start All/Stop, project selector, service/runtime lists) live in
`ContentView` but are part of the dashboard experience.

### DB-1 — Start All / Stop buttons are no-ops · **broken**
- **Element:** Sidebar `start_all_btn` / `stop_all_btn`.
- **Current:** Both are wired to empty closures (`Button("▶ Start All") {}`); clicking does nothing.
- **Expected:** Start All should start every configured service; Stop should stop them all.
- **HOW IT SHOULD BE:** These are the most visible primary actions on the screen and must drive the `ServiceManager`/`ServiceBackend` (which already supports `start`/`stop`/`list`). Start All should iterate services in dependency order, show per-service progress, and refresh the service list and stats. Stop should reverse-order stop running services. Buttons should reflect in-progress state (disabled + spinner) and surface failures inline.

### DB-2 — CPU / Memory cards always read 0 in production · **wrong**
- **Element:** `StatsCard` CPU and Memory tiles.
- **Current:** `services ls --json` carries no cpu/mem/pid/uptime, so production always shows `0%` / `0 MB`; non-zero values only appear under test doubles.
- **Expected:** Cards should show real resource usage, or not claim to.
- **HOW IT SHOULD BE:** Either extend the CLI (`services ls --json`) to emit real per-service cpu/mem/pid/uptime and surface it live, or hide the CPU/Memory cards in production until resource monitoring exists. A permanently-zero readout that looks live is worse than no card. The "Running n/total" card is honest and should stay.

### DB-3 — Service selection is cosmetic · **wrong**
- **Element:** Service `List` selection (`selectedService`).
- **Current:** Selecting a service only changes row highlight; logs are global and all other tabs are stubs, so selection drives nothing.
- **Expected:** Selecting a service should scope the logs/config/connection tabs to that service (as the prototype keys every tab off the selected service).
- **HOW IT SHOULD BE:** Selection should be the single source of truth for the tab content below — the Logs tab filters to that service, Config edits that service, Connection shows that service's strings. Until those tabs exist, selection should at least scope the logs query.

### DB-4 — Logs are file-scraped with no backing command · **wrong**
- **Element:** Logs data source (`DataStore.fetchLogs()`).
- **Current:** Reads the newest file in `~/.rawenv/logs` (last 50 lines, `prefix(8)` as time), infers level by substring match on `ERROR`/`WARN`; no `rawenv logs` command backs it.
- **Expected:** Logs should come from a stable, structured source.
- **HOW IT SHOULD BE:** Add a `rawenv logs [--service x] [--json]` command emitting structured `{time, level, service, msg}` records, and have the dashboard consume that. Level should be authoritative, not guessed from substrings, and timestamps should be parsed rather than sliced from the first 8 characters.

### DB-5 — Config tab is a stub · **missing**
- **Element:** `.config` tab.
- **Current:** Renders a centered literal `Text("Configuration")` — no display, edit, save, or reset.
- **Expected:** A per-service config editor (the prototype specifies `port`, `max_connections`, `shared_buffers`, `work_mem`, etc., plus Full Editor / Edit Raw File / Save & Restart / Reset to defaults).
- **HOW IT SHOULD BE:** The Config tab should render the selected service's configuration as editable, typed fields with validation, an "Edit Raw File" escape hatch, and Save & Restart / Reset actions that write to the service config and restart it. Until built, the tab should not present a bare placeholder that looks broken.

### DB-6 — Connection tab is a dead stub (functionality hidden elsewhere) · **missing**
- **Element:** `.connection` tab.
- **Current:** Renders `Text("Connection Info")` only; the real connection UI (string + working Copy + mode toggles) lives in a separate `Connections` sidebar destination.
- **Expected:** The dashboard Connection tab should show connection strings + copy buttons for the selected service.
- **HOW IT SHOULD BE:** At minimum, the tab should link/redirect to the working Connection Manager so it is not a dead end. Better, it should inline the selected service's connection string with a Copy button and mode toggle, consistent with `ConnectionsView`.

### DB-7 — Logs never update; no filter / tail / auto-scroll · **missing**
- **Element:** `.logs` tab.
- **Current:** Logs load once in `.task`; no timer, refresh, live tail, level/service filter, or jump-to-latest.
- **Expected:** Live-updating logs with filtering and auto-scroll.
- **HOW IT SHOULD BE:** The Logs tab should tail the source on an interval (or via a follow stream), auto-scroll to the newest line with a "pause/jump to latest" affordance, and offer per-level and per-service filters plus a search field. New lines should appear without recreating the view.

### DB-8 — Cell & Backups tabs are stubs present in the live tab bar · **missing**
- **Element:** `.cell` and `.backups` tabs.
- **Current:** Each is a single centered label; the prototype specifies a rich Cell isolation panel (mechanism, fs/network scope, editable mem/CPU limits, PID, live usage, "View sandbox profile").
- **Expected:** Either implemented panels or hidden pills.
- **HOW IT SHOULD BE:** Build the Cell panel (isolation backend, scope, editable limits, live usage) and a Backups panel, or hide these pills behind a feature flag until implemented so users don't click into empty tabs.

### DB-9 — No empty-state messaging · **missing**
- **Element:** Service list & logs list when data is empty.
- **Current:** Zero services/logs render completely blank lists with no guidance; "Running 0/0" gives no direction.
- **Expected:** Friendly empty states with next-step CTAs.
- **HOW IT SHOULD BE:** When no services exist, show "No services yet" with a CTA to add one (`rawenv add …` or the Discovery screen). When no logs exist, explain logs appear once services start. (See ST-2/ST-3 for the shared component.)

### DB-10 — Dashboard view model rebuilt on every navigation · **polish**
- **Element:** `DashboardViewModel` lifecycle.
- **Current:** Each navigation to `.dashboard` builds a fresh VM, discarding selection/tab state.
- **Expected:** Selection and active tab should persist across navigation.
- **HOW IT SHOULD BE:** Hoist the dashboard VM (or its UI state) into a longer-lived owner so returning to the dashboard restores the previously selected service and tab, rather than resetting to defaults each time.

---

## 2. Projects / Discovery

Flow: Discovery scan → Project list → Setup/configure → Install → Done. Findings
derived against the design prototype (`screens-gui.js`).

### PR-1 — Project rows always open the same hard-coded project · **broken**
- **Element:** Project list row navigation.
- **Current:** Every row calls `navigate('project-setup')` and setup is hard-coded to render the "utilio" project regardless of which row was clicked.
- **Expected:** Clicking a row should open that specific project's detected stack.
- **HOW IT SHOULD BE:** `navigate()` should accept a payload with the project id/path; the setup screen should render that project's detected runtimes/services/connections dynamically. Every project must get its own accurate setup experience.

### PR-2 — Install animation always succeeds (no failure branch) · **broken**
- **Element:** 10-step install animation.
- **Current:** Every step turns green; no failure state, retry, or log.
- **Expected:** Steps can fail with a red error, message, Retry, and View Log.
- **HOW IT SHOULD BE:** A failing step should turn red with the inline reason, the progress bar should halt, and the primary button should become Retry / View Log. Partial progress should report which services started. This mirrors real resolver/network/sudo failures.

### PR-3 — Filter input does nothing · **broken**
- **Element:** "Filter…" text input (project list).
- **Current:** No input handler; typing does not filter rows.
- **Expected:** Real-time filtering by name/path/stack tags.
- **HOW IT SHOULD BE:** A debounced handler should filter rendered rows by name, path, and tags; zero matches should show an inline "No projects match your filter" with a clear-filter action.

### PR-4 — "+ Add custom path" button is inert · **broken**
- **Element:** Add custom path button (scan screen).
- **Current:** No click handler.
- **Expected:** Opens a directory picker to add a scan path.
- **HOW IT SHOULD BE:** Present a directory picker; the chosen folder is added to scan locations and scanned immediately. This is the key escape hatch when default locations miss a project.

### PR-5 — "Scan full disk" button is inert · **broken**
- **Element:** Scan full disk button (scan screen).
- **Current:** No click handler.
- **Expected:** Initiates a full-disk scan.
- **HOW IT SHOULD BE:** Warn about duration, then scan all accessible directories with a live found-count and a cancel affordance.

### PR-6 — "↻ Force rescan all" button is inert · **broken**
- **Element:** Force rescan all (scan screen).
- **Current:** No click handler.
- **Expected:** Invalidates cache for all locations and re-scans.
- **HOW IT SHOULD BE:** Clear cached results, reset rows to pending, re-scan sequentially with "cached" badges removed and found-counts updating live.

### PR-7 — "↻ Full rescan" button is inert · **broken**
- **Element:** Full rescan (project list).
- **Current:** No click handler.
- **Expected:** Triggers a full rescan and refreshes the list.
- **HOW IT SHOULD BE:** Invalidate all cached results, re-discover, then refresh the list — the list-level equivalent of the scan screen's force rescan.

### PR-8 — "+ Add project manually" button is inert · **broken**
- **Element:** Add project manually (project list).
- **Current:** No click handler.
- **Expected:** Lets the user point at an existing project directory.
- **HOW IT SHOULD BE:** Open a directory picker; run detection on the path and add it to the list with its detected stack. Essential for the empty-state scenario.

### PR-9 — "Keep remote ✓" button is inert · **broken**
- **Element:** Keep remote button (S3 connection card, setup).
- **Current:** No click handler.
- **Expected:** Confirms the remote connection is kept and updates state.
- **HOW IT SHOULD BE:** Mark the card resolved, update its badge, increment the summary "Keep" count, and show a selected/active state.

### PR-10 — Scan progress is a static snapshot · **broken**
- **Element:** Scan progress animation.
- **Current:** The "⟳ scanning…" row never progresses; pending rows never advance.
- **Expected:** Animated progress that advances through locations with live counts.
- **HOW IT SHOULD BE:** The active row spins with an incrementing found-count, resolves to "✓ done", then activates the next pending row; on completion "View Projects →" auto-navigates/enables. Reuse the installer's interval-based progression.

### PR-11 — Setup summary counts & footprint are static · **wrong**
- **Element:** Summary bar ("Install 4 · Migrate 0 · Keep 2 · Footprint ~462MB").
- **Current:** Static text that ignores card decisions and the version select.
- **Expected:** Live recalculation as decisions change.
- **HOW IT SHOULD BE:** Choosing Keep/Migrate/Install on a card should adjust the counts; the footprint should recompute from what will actually be installed vs kept, giving confidence before "Apply & Start".

### PR-12 — Node version select has no effect · **wrong**
- **Element:** Node.js version `<select>` (setup).
- **Current:** Changing it doesn't alter install steps or footprint; install always says 22.15.0.
- **Expected:** The selected version propagates to install steps, footprint, and the actual install.
- **HOW IT SHOULD BE:** The user's chosen version is the single source of truth: it flows to the install step list, footprint estimate, and execution.

### PR-13 — Project count inconsistent with rendered rows · **wrong**
- **Element:** List/scan footer count.
- **Current:** Footer says "14 projects" but only 8 rows render.
- **Expected:** Count matches rendered rows, or clearly states "Showing 8 of 14".
- **HOW IT SHOULD BE:** Render all discovered projects, or say "Showing 8 of 14 projects" with a way to see the rest, using a single source of truth across scan and list screens.

### PR-14 — Install step versions decoupled from configuration · **wrong**
- **Element:** Install step versions (installing screen).
- **Current:** Shows "PostgreSQL 18.2" / "Node.js 22.15.0", ignoring configured versions and the Postgres-16 product pin.
- **Expected:** Step versions match exactly what was configured/selected.
- **HOW IT SHOULD BE:** Generate the install step list from the setup screen's final state so it reflects the resolved versions (e.g. "Installing PostgreSQL 16.x.x"), aligning with CLI version resolution.

### PR-15 — Details panel on project list · **missing**
- **Element:** Project list row preview.
- **Current:** Clicking a row jumps straight to full-screen setup with no preview.
- **Expected:** A details/preview panel before committing to setup.
- **HOW IT SHOULD BE:** Selecting a row opens a side panel/expanded section showing detected runtimes/services/versions/status, with a "Set Up →" button to continue — enabling quick scanning of many projects.

### PR-16 — No empty state when zero projects found · **missing**
- **Element:** Project list empty state.
- **Current:** Always renders 8 hard-coded rows; no empty state.
- **Expected:** Friendly empty state with the add/scan CTAs.
- **HOW IT SHOULD BE:** When discovery finds nothing, show "No projects found in scanned locations" with working "+ Add custom path", "Scan full disk", and "+ Add project manually" CTAs (the currently-decorative buttons).

### PR-17 — No failed-detection state · **missing**
- **Element:** Setup card detection.
- **Current:** Detection always "succeeds"; unparseable manifests/conflicts/unsupported runtimes aren't handled.
- **Expected:** Per-card warning states with manual override.
- **HOW IT SHOULD BE:** Unparseable/conflicting manifests should put the affected card into a ⚠️ warning state with the error and a manual runtime/version picker — mirroring real CLI gaps (bun, MariaDB, MSSQL, PHP mismatches).

### PR-18 — No missing-binary / unsupported-version surfacing · **missing**
- **Element:** Setup card resolver feedback.
- **Current:** No indication when a detected runtime/version is unavailable in the resolver; Apply would fail late.
- **Expected:** Inline error on the card before Apply.
- **HOW IT SHOULD BE:** When the resolver can't fulfill a requirement, show its message ("Unknown package/version, supported: …") on the card and exclude that item from Apply until resolved.

### PR-19 — No DNS sudo permission handling · **missing**
- **Element:** "Setting up DNS (utilio.test)" install step.
- **Current:** Always shows success; ignores that `.test` DNS needs elevated permissions.
- **Expected:** Detect when sudo is required and prompt.
- **HOW IT SHOULD BE:** When writing `/etc/hosts` requires elevation, pause with a clear explanation and a guided OS auth prompt; never silently "succeed" a step that would fail in production.

### PR-20 — No scan cancel / long-running affordance · **missing**
- **Element:** Scan controls.
- **Current:** No way to cancel an in-progress scan or use partial results.
- **Expected:** Cancel button and partial-result access.
- **HOW IT SHOULD BE:** Show a Cancel/Stop during scanning; enable "View Projects →" as soon as one project is found; show a time estimate or progress for long scans.

### PR-21 — Modal success state doesn't propagate to the card/summary · **polish**
- **Element:** Migrate/Keep/Install MinIO modals.
- **Current:** Success ("✓ Migrated") shows only on the modal button; the originating card badge and summary don't update, and it resets if re-opened.
- **Expected:** Success persists on the card and updates the summary.
- **HOW IT SHOULD BE:** After a successful modal action, update the originating card badge (e.g. "✓ Migrated to rawenv"), adjust summary counts, and show the confirmed state on re-open.

---

## 3. AI Chat

`AIChatView` (GUI) and the TUI chat surface, backed by a provider cascade.

### AI-1 — Markdown tables render as raw pipes · **broken**
- **Element:** Message renderer.
- **Current:** The renderer only handles fenced/inline code, bold, and newlines; tables (and headings/lists/links) display as raw pipe-delimited text. The canned "optimize memory" reply contains a table.
- **Expected:** GFM tables, headings, lists, and links render as styled elements.
- **HOW IT SHOULD BE:** Use a richer markdown parser supporting tables, headings (`#`), lists, and links, since real LLM output uses these constantly. Tables should render as proper grids with aligned columns and subtle separators. Canned replies must never emit formatting the renderer can't handle.

### AI-2 — Provider picker is ignored · **broken**
- **Element:** Provider `<select>` (GUI) / chip selector (TUI).
- **Current:** GUI select has no `onchange`; `sendAIMessage()` is hardcoded to the Groq→Cerebras cascade. TUI `_tuiAIProvider` is written but never read.
- **Expected:** Selecting a provider routes requests through that provider's endpoint/key.
- **HOW IT SHOULD BE:** The picker must drive the active provider (e.g. "Ollama (local)" → local endpoint), set the cascade's starting point, persist across navigation, and confirm the active model in the header.

### AI-3 — "No data sent to third parties" label is false · **wrong**
- **Element:** Content-meta privacy label.
- **Current:** Header says "No data sent to third parties" while `sendAIMessage()` POSTs the system prompt (project path, stack, ports, memory) and history to api.groq.com / api.cerebras.ai.
- **Expected:** The label should accurately reflect the active provider and what leaves the machine.
- **HOW IT SHOULD BE:** Make the label dynamic and provider-aware ("Local only" for Ollama; "Sent to Groq"/"Sent to Cerebras" for cloud). Redact project paths and env vars before sending (extend the native `context.zig` secret masking to the prototype layer). Users must have informed consent.

### AI-4 — No error or loading states · **missing**
- **Element:** Whole chat flow.
- **Current:** All errors (missing key, 401, network failure) are swallowed into the mock fallback; no spinner, toast, or offline indicator; users can't tell canned from live answers.
- **Expected:** Thinking indicator, offline/canned badge, and actionable error messages.
- **HOW IT SHOULD BE:** Show a typing indicator while awaiting a response; mark fallback answers ("⚡ Offline answer"); show inline error bubbles for hard errors ("Set your API key in Settings → AI"); disable/debounce input during pending requests. (See ST-15/ST-16.)

### AI-5 — Clear loses the proactive context seed · **polish**
- **Element:** Clear/Reset (`Clear` / `^L:clear`).
- **Current:** Clearing leaves a plain "Chat cleared." message without restoring the project-aware greeting.
- **Expected:** Clearing restores the proactive context seed.
- **HOW IT SHOULD BE:** Clear should reset to the initial state including the greeting that shows current project context, preserving the assistant's "aware" personality — or offer "Clear" (with seed) vs "New topic" (minimal).

### AI-6 — Unbounded chat history · **polish**
- **Element:** Conversation history (`window._aiHistory`).
- **Current:** No truncation; long sessions grow indefinitely (the native `ChatSession` truncates by token budget, the prototype does not).
- **Expected:** Token/message-budget truncation or summarization.
- **HOW IT SHOULD BE:** Mirror the native token-budget eviction; collapse older messages behind "Show earlier messages" to keep the DOM bounded and stay within provider context limits.

### AI-7 — Input not disabled during in-flight request · **polish**
- **Element:** Chat input (`#gui-ai-input`).
- **Current:** Users can fire concurrent `sendAIMessage` calls; replies append in non-deterministic order.
- **Expected:** Input disabled/debounced while a request is in flight.
- **HOW IT SHOULD BE:** Show a send loading state; queue or hold the next message; ensure replies always appear in conversation order regardless of network timing.

---

## 4. Connections & Tunnel

`ConnectionsView` (sidebar **Connections**) and `TunnelView` (sidebar **Tunnel**).

### CT-1 — Connection mode switches never persist · **broken**
- **Element:** Use Remote / Use Local / Proxy Remote buttons.
- **Current:** Tapping updates the in-memory badge/string but writes no config and resets on reload.
- **Expected:** Mode choice persists and affects the running environment.
- **HOW IT SHOULD BE:** Persist the selection (write to `rawenv.toml` via a CLI call); restore it on restart; route the active environment through the chosen mode so "Use Remote" actually uses the remote endpoint.

### CT-2 — Proxy mode shows no real proxy URL · **broken**
- **Element:** Proxy Remote mode.
- **Current:** Falls back to `connection.original` because `DataStore` always sets `proxy = nil`.
- **Expected:** Display a real `local → remote` proxy mapping.
- **HOW IT SHOULD BE:** Parse proxy config from CLI/project config into the `proxy` field and show both local proxy endpoint and remote target (e.g. `localhost:7700 → ms.myapp.com:7700`).

### CT-3 — Tunnel port field accepts garbage · **broken**
- **Element:** Tunnel port `TextField`.
- **Current:** Accepts any text (non-numeric, empty, out-of-range) and interpolates it straight into the SSH command; no validation.
- **Expected:** Numeric 1–65535 only, with error feedback.
- **HOW IT SHOULD BE:** Use a numeric formatter rejecting non-digits, validate the 1–65535 range with inline error styling, and disable "Create Tunnel" while invalid.

### CT-4 — Generated command ignores selected provider · **wrong**
- **Element:** Generated tunnel command.
- **Current:** Always shows the SSH form regardless of provider (cloudflared/ngrok/rathole still show SSH).
- **Expected:** Command matches the selected provider's syntax.
- **HOW IT SHOULD BE:** A provider-aware generator: bore → `bore local <port> --to <relay>`; cloudflared → `cloudflared tunnel --url localhost:<port>`; ngrok → `ngrok http <port>`; etc., so the shown command is copy-runnable.

### CT-5 — Provider options mismatch the AC · **wrong**
- **Element:** Tunnel provider picker.
- **Current:** Offers bore/cloudflared/ngrok/rathole; the AC specifies bore/cloudflared/ngrok/SSH.
- **Expected:** Include SSH (or reconcile the AC), with each option generating its own command.
- **HOW IT SHOULD BE:** If SSH is a valid method (the always-shown SSH command implies it is), make it a selectable option; otherwise label the SSH block as bore/SSH output and have other providers emit their own commands.

### CT-6 — TunnelView not wired to repository/settings · **wrong**
- **Element:** `TunnelView()` construction.
- **Current:** Built with the default initializer; ignores the user's saved `network.tunnelProvider` / `network.relayServer`.
- **Expected:** Seed the VM from persisted settings via the repository.
- **HOW IT SHOULD BE:** `ContentView` should pass `appState.repository` and seed `provider`/`relayServer` from saved settings (currently masked only because defaults coincide).

### CT-7 — Create Tunnel is simulated, not real · **wrong**
- **Element:** Create Tunnel / Active Tunnels.
- **Current:** Appends a simulated entry with a random URL; status dot always green; Stop just removes the row.
- **Expected:** Start a real tunnel, show the real URL/status, and terminate on Stop.
- **HOW IT SHOULD BE:** Invoke the provider binary (or rawenv CLI tunnel command); show the real public URL and process state (green/red/grey); Stop sends a terminate signal; surface connection failures/timeouts.

### CT-8 — Hardcoded `localhost` for every local endpoint · **wrong**
- **Element:** `DataStore.fetchConnections` local value.
- **Current:** Maps every connection to `local: "localhost"` with no port.
- **Expected:** Real local endpoint incl. port from project config.
- **HOW IT SHOULD BE:** Derive the local URL from the project's ports/hostnames so cards show `localhost:5432`, `localhost:6379`, etc. — directly usable strings.

### CT-9 — Connections empty state · **missing**
- **Element:** Connections screen with no data.
- **Current:** Only the title/subtitle render; the rest is blank.
- **Expected:** Empty-state message explaining detection and next steps.
- **HOW IT SHOULD BE:** Show "No connections detected" with guidance ("rawenv reads `DATABASE_URL`, `REDIS_URL`, etc.; run `rawenv init` / add one and rescan"). (See ST-19.)

### CT-10 — No dependency graph / map visualization · **missing**
- **Element:** Service dependency visualization.
- **Current:** CLI from/to pairs are flattened into cards; no graph.
- **Expected:** A node/edge graph of service relationships (per AC).
- **HOW IT SHOULD BE:** Add a directed graph (nodes = services, edges = connections) above the detail cards, updating reactively when connections change.

### CT-11 — Alternative service row + Install action · **missing**
- **Element:** Connection card `alternative` field.
- **Current:** The model has `alternative` but the data layer never populates it and the view never renders it or an Install button.
- **Expected:** Show an "Alternative" row + Install when a local substitute exists.
- **HOW IT SHOULD BE:** Detect compatible local substitutes (e.g. MinIO for S3), render an "Alternative:" row, and an "Install MinIO" button that installs via the store — matching the prototype's S3 card.

### CT-12 — No command Copy button on Tunnel · **missing**
- **Element:** Generated command block.
- **Current:** Text is selectable but has no dedicated Copy button.
- **Expected:** A Copy button consistent with Connection cards.
- **HOW IT SHOULD BE:** Add a Copy button/clipboard icon next to the command that copies it and shows "Copied!" feedback, matching the card pattern.

### CT-13 — Tunnel screen lacks tabs (Active / Settings / Logs) · **missing**
- **Element:** Tunnel screen structure.
- **Current:** A single flat view with create form + active list.
- **Expected:** Tabs for Active Tunnels, Settings, and Logs (per prototype).
- **HOW IT SHOULD BE:** Organize into "Active Tunnels", "Settings" (provider, relay, custom domain, security), and "Logs" (request viewer with Clear/Export and a request/error/blocked summary).

### CT-14 — No custom domain field · **missing**
- **Element:** Tunnel custom domain.
- **Current:** No custom domain configuration exists.
- **Expected:** A validated custom-domain field in Tunnel settings.
- **HOW IT SHOULD BE:** Add a "Custom Domain" field (e.g. `dev.myapp.com`) with format validation and DNS-required hints, supporting stable URLs for webhooks/demos.

### CT-15 — No security controls · **missing**
- **Element:** Tunnel security (auth / IP allowlist / auto-close).
- **Current:** None exist.
- **Expected:** Auth-required toggle, IP allowlist, auto-close timer.
- **HOW IT SHOULD BE:** Add a Security section: an "Auth Required" toggle (basic auth on the endpoint), an IP allowlist editor (IPs/CIDRs), and an auto-close timer — protecting exposed local services.

### CT-16 — No request log viewer · **missing**
- **Element:** Tunnel Logs tab.
- **Current:** No request logging.
- **Expected:** A chronological request log with stats and Clear/Export.
- **HOW IT SHOULD BE:** Show timestamp/method/path/status/source-IP rows, a totals summary (requests/errors/blocked), and Clear/Export actions for visibility into tunnel traffic.

### CT-17 — No per-tunnel live stats · **missing**
- **Element:** Active tunnel rows.
- **Current:** Show only the URL mapping + a static green dot.
- **Expected:** Live latency, uptime, and bytes transferred.
- **HOW IT SHOULD BE:** Each active row shows latency (ms), uptime, and bytes up/down, updating on an interval to help monitor tunnel health.

---

## 5. Deploy

`DeployView` + `DeployVM` + `DeployEngine`, sidebar **Deploy**. Tabs: terraform,
ansible, containerfile (titled "Image"), deployLog.

### D-1 — `Start Deploy` runs a real, unconfirmed `terraform apply -auto-approve` · **wrong** 🔴
- **Element:** `deploy_start_button` → `DeployEngine.runDeploy()`.
- **Current:** Shells `terraform init` → `plan` → `apply -auto-approve` in the process CWD with no confirmation; bypasses the CLI's `--confirm` safety gate entirely.
- **Expected:** No irreversible cloud provisioning from a single unconfirmed click.
- **HOW IT SHOULD BE:** Gate Start Deploy behind an explicit confirmation dialog, and route it through the CLI's `deploy apply` (which enforces `--confirm` and dry-run by default). Never invoke `terraform apply -auto-approve` directly from the GUI. **This is the highest-priority risk in the app.**

### D-2 — Two conflicting `DeployTab` enums (dead code / drift) · **wrong**
- **Element:** `DeployViewModel.DeployTab` (3 cases) vs `DeployViewTab` (4 cases).
- **Current:** The view uses its own 4-case enum and never reads `viewModel.selectedTab`; the VM's `selectedTab`/`currentContent`/`copyCurrentContent()` are dead from the UI's view, and the two disagree on tab count.
- **Expected:** One source of truth for tabs.
- **HOW IT SHOULD BE:** Collapse the duplicate enums into one; have the view drive `viewModel.selectedTab` and call `copyCurrentContent()` instead of re-implementing clipboard logic, removing the dead VM path.

### D-3 — Deploy Log error text is hardcoded · **wrong**
- **Element:** Error box headline.
- **Current:** Always shows "⚠️ Redis failed: port 6379 already in use" regardless of the real failure (usually missing-terraform).
- **Expected:** Show the actual failed step and stderr.
- **HOW IT SHOULD BE:** Derive the headline from the last `isError` log entry (the real error is already appended), so users see what actually went wrong without scrolling.

### D-4 — "🤖 AI Fix" is canned/scripted · **wrong**
- **Element:** `deploy_ai_fix` → `applyAIFix()`.
- **Current:** Appends two canned lines, sets `progress = 1.0`, clears `hasError`; no real diagnosis.
- **Expected:** Real diagnosis or honest labeling.
- **HOW IT SHOULD BE:** Either perform a real AI-assisted diagnosis of the failed step (feed the actual error to the assistant and propose a concrete fix), or relabel it as a demo so it doesn't imply a real fix occurred.

### D-5 — Save button is a no-op · **broken**
- **Element:** `CodeTab` Save.
- **Current:** `Button("Save") {}` — empty closure, no feedback.
- **Expected:** Writes the generated config to disk.
- **HOW IT SHOULD BE:** Save should write to `terraform/` / `ansible/` / `Containerfile` (mirroring the CLI's non-`--json` path) and confirm with a modal listing written files.

### D-6 — "Change port" error action is a no-op · **broken**
- **Element:** Deploy Log error → Change port.
- **Current:** Empty closure.
- **Expected:** Lets the user change the conflicting port and retry.
- **HOW IT SHOULD BE:** Open a port input, apply it to the failing service config, and re-run — or remove the button until implemented.

### D-7 — "Skip" error action is a no-op · **broken**
- **Element:** Deploy Log error → Skip.
- **Current:** Empty closure.
- **Expected:** Skips the failing step and continues.
- **HOW IT SHOULD BE:** Mark the step skipped, continue the remaining steps, and record the skip in the log — or remove until implemented.

### D-8 — Deploy reads process CWD, not the active project · **broken**
- **Element:** `DataStore.projectPath`.
- **Current:** Defaults to `currentDirectoryPath` and is never set to `appState.activeProject.path`; a Finder-launched `.app` has CWD `/`, so Deploy is permanently blank, and switching projects changes nothing.
- **Expected:** Deploy reflects the selected project.
- **HOW IT SHOULD BE:** Feed `DataStore` the active project's path so generation reads that project's `rawenv.toml` and works regardless of launch context.

### D-9 — No syntax highlighting in code tabs · **missing**
- **Element:** `CodeTab` code rendering.
- **Current:** Single monochrome `Color.textPrimary` string; the prototype colors keywords/strings.
- **Expected:** Syntax-highlighted code (AC requires it).
- **HOW IT SHOULD BE:** Tokenize and color keywords/strings/comments per language (HCL/YAML/Dockerfile), with horizontal scroll for long lines instead of wrapping.

### D-10 — No explicit Generate / regenerate trigger · **missing**
- **Element:** Generate flow.
- **Current:** Generation runs once implicitly on view load; no button, no refresh; editing settings/`rawenv.toml` doesn't re-trigger it.
- **Expected:** An explicit Generate/Regenerate control.
- **HOW IT SHOULD BE:** Provide a "Generate" / "Regenerate" button that re-runs `deploy generate` on demand and after relevant changes, with clear loading and success/error feedback.

### D-11 — No Deploy/Run/Build action on code tabs · **missing**
- **Element:** Code-tab primary actions.
- **Current:** Code tabs have only Copy + (dead) Save; the prototype gives each a "🚀 Deploy Now" / "Run Playbook" / "Build Image".
- **Expected:** Per-tab primary action that jumps to the Deploy Log.
- **HOW IT SHOULD BE:** Each code tab gets a primary action that triggers the corresponding deploy/run/build (through the gated CLI) and switches to the Deploy Log to show progress.

### D-12 — No provider selector · **missing**
- **Element:** Provider control.
- **Current:** Provider is hardcoded to `hetzner`; only a static "Hetzner CX22" label appears.
- **Expected:** A Hetzner/AWS/DigitalOcean/Custom SSH selector driving generation.
- **HOW IT SHOULD BE:** A provider selector/stats row that regenerates the configs for the chosen target and surfaces provider-specific options.

### D-13 — No image format selector · **missing**
- **Element:** Image (containerfile) tab.
- **Current:** Shows only generated text; the prototype offers OCI / VM / Dockerfile cards.
- **Expected:** A format selector.
- **HOW IT SHOULD BE:** Offer OCI / VM image / Dockerfile options that change the generated artifact and build command.

### D-14 — No empty state for unconfigured project · **missing**
- **Element:** Code tabs when generation fails/returns empty.
- **Current:** Every failure is swallowed to an empty config; the tab shows a silent blank `ScrollView`.
- **Expected:** A helpful empty/error state.
- **HOW IT SHOULD BE:** Show "No `rawenv.toml` found — run `rawenv init` to generate deployment configs", disable Copy/Save when empty, and distinguish "not generated" from "generation failed". (See ST-11/ST-12/ST-14.)

### D-15 — No re-run after a successful deploy · **missing**
- **Element:** Start button visibility.
- **Current:** Start only shows when `logs.isEmpty`; after a successful run there is no way to start again (only the error-state Retry exists).
- **Expected:** A way to reset/clear and re-run.
- **HOW IT SHOULD BE:** Offer "Deploy again" / "Clear log" so a successful deploy can be re-run, not just failed ones.

### D-16 — No Cancel path for a running deploy · **missing**
- **Element:** Deploy engine.
- **Current:** Once `runDeploy` starts there is no cancellation.
- **Expected:** A Cancel button that stops the run.
- **HOW IT SHOULD BE:** Add a cancellation path that terminates the running process after the current step and reports partial progress.

### D-17 — No copy/export of the deploy log · **missing**
- **Element:** Deploy Log.
- **Current:** No copy or export.
- **Expected:** Copy/export of the full log.
- **HOW IT SHOULD BE:** Add Copy and Export actions so users can share or archive a deploy log for debugging.

### D-18 — Containerfile tab labeled "Image" vs prototype "Image Build" · **polish**
- **Element:** Tab title.
- **Current:** Titled "Image"; prototype says "Image Build".
- **Expected:** Consistent labeling.
- **HOW IT SHOULD BE:** Align the label with the design ("Image Build") or update the design — minor but a drift signal.

---

## 6. Menu Bar

macOS `MenuBarExtra` popover, the native `rawenv menubar`, and the (unrendered)
raylib menu bar screen.

### MB-1 — Dashboard button doesn't raise the window · **broken**
- **Element:** `menubar_open_dashboard`.
- **Current:** Calls `navigate(to: .dashboard)` but never activates/raises the main window; if hidden/minimized, nothing visible happens.
- **Expected:** Navigates AND focuses the main window.
- **HOW IT SHOULD BE:** Also call `NSApp.activate(ignoringOtherApps: true)`, order the main window front, and dismiss the popover so the dashboard appears immediately regardless of window state.

### MB-2 — Native CLI menu bar service rows are non-interactive · **broken**
- **Element:** Native `rawenv menubar` service rows.
- **Current:** `action = null`; rows can't start/stop and all show the same `●` with no status differentiation.
- **Expected:** Interactive rows with differentiated status.
- **HOW IT SHOULD BE:** Each row toggles the service (start/stop) and shows differentiated status (green `●` running / red `●` stopped). If full interactivity isn't feasible in NSMenu, at least show accurate differentiated status.

### MB-3 — Native "Open TUI" / "Open GUI" items do nothing · **broken**
- **Element:** Native menu items.
- **Current:** `action = null`; non-functional placeholders.
- **Expected:** Launch the TUI / GUI.
- **HOW IT SHOULD BE:** "Open TUI" spawns a terminal running `rawenv tui`; "Open GUI" launches/activates the app bundle. If unimplemented, remove or disable (grey out) the items.

### MB-4 — Running count is always green · **wrong**
- **Element:** Header "X/Y running" label.
- **Current:** Always green, even at "0/5 running".
- **Expected:** Contextual color.
- **HOW IT SHOULD BE:** Green when services run; neutral/warning when zero, giving an at-a-glance health signal.

### MB-5 — Service toggle pill has no accessibility identity · **wrong**
- **Element:** Custom toggle pill.
- **Current:** No `accessibilityIdentifier` and not recognized as a switch; UI tests for `menubar_service_toggle` silently fail to find it.
- **Expected:** Identifiable and operable by VoiceOver/automation.
- **HOW IT SHOULD BE:** Convert to a native `Toggle` (inherits traits) or annotate with `.accessibilityIdentifier("menubar_service_toggle_<name>")` + button/toggle traits + a label. (See also CC-7.)

### MB-6 — Project row empty state contradicts the footer · **wrong**
- **Element:** Project row vs footer when no project.
- **Current:** Row shows placeholder "my-app" while the footer shows "no project".
- **Expected:** Consistent, honest text.
- **HOW IT SHOULD BE:** Show a single consistent "No project" in both places; remove the hardcoded "my-app" fallback.

### MB-7 — Native CLI header hardcodes running count to 0 · **wrong**
- **Element:** Native `rawenv menubar` header.
- **Current:** Hardcodes `0` as the numerator ("rawenv — 0/{d} running").
- **Expected:** Real running count.
- **HOW IT SHOULD BE:** Compute the real count (reuse the already-correct `menubar.zig::runningCount()` / parse `services ls`); a hardcoded zero is actively misleading.

### MB-8 — UI test identifiers don't match the view · **wrong**
- **Element:** `RawenvUITests` menu bar identifiers.
- **Current:** Tests reference `menubar_popover`/`menubar_running_count`/`menubar_service_list`/`menubar_service_toggle` which don't exist (view exposes `menubar_view`, `menubar_service_<name>`, `menubar_start_all`, `menubar_open_dashboard`); tests pass without asserting.
- **Expected:** Tests exercise real controls and fail meaningfully.
- **HOW IT SHOULD BE:** Reconcile identifiers (add the expected ones or update tests), and replace `waitForExistence` skip-guards with hard assertions so mismatches surface as failures.

### MB-9 — Project row isn't tappable (no switching) · **missing**
- **Element:** Project row + "▾" chevron.
- **Current:** Static HStack with a chevron that implies a dropdown but has no tap target/menu.
- **Expected:** Tapping opens a project switcher.
- **HOW IT SHOULD BE:** Make it a `Menu` populated from `appState.managedProjects`; selecting one sets `activeProject` and refreshes the service list — matching the sidebar `project_selector`.

### MB-10 — Native CLI menu bar has no project concept · **missing**
- **Element:** Native `rawenv menubar`.
- **Current:** Only reads `[services.*]` from the CWD's `rawenv.toml`; can't show/switch projects.
- **Expected:** Show the current project and ideally switch.
- **HOW IT SHOULD BE:** Read `[project]` for the name in the header; if multiple projects are discovered, offer a switch submenu.

### MB-11 — Raylib menu bar screen is never rendered · **missing**
- **Element:** `src/gui/screens/menubar.zig`.
- **Current:** Exists only as a model with tests; no render call in the draw loop.
- **Expected:** Rendered, or explicitly deprecated.
- **HOW IT SHOULD BE:** Wire `MenuBarState` into `app.zig`'s draw loop with a render function (the model logic is already correct/tested), or mark the screen deprecated/removed if the raylib GUI is being retired.

### MB-12 — Dangling separators in service metrics · **polish**
- **Element:** Service row "port · mem · uptime".
- **Current:** nil/empty `mem`/`uptime` produce ":5432 ·  · ".
- **Expected:** Only non-empty parts joined.
- **HOW IT SHOULD BE:** Filter nil/empty values before joining with " · " so output is clean (":5432" or ":5432 · 128MB").

### MB-13 — Toggle pill hardcodes green, ignores theme · **polish**
- **Element:** Toggle pill color.
- **Current:** Hardcoded `Color.green`, ignores `ThemeManager.accentColor`.
- **Expected:** Uses the theme accent.
- **HOW IT SHOULD BE:** Use `themeManager.accentColor` for "on" and neutral gray for "off" so the menu bar respects the user's theme.

### MB-14 — Footer version string hardcoded · **polish**
- **Element:** Footer `v0.2.0`.
- **Current:** String literal that will drift on version bumps.
- **Expected:** Derived from build/bundle info.
- **HOW IT SHOULD BE:** Read `CFBundleShortVersionString` (or a build-time constant) so it always matches the binary.

### MB-15 — Dead `.menuBar` in-window destination · **polish**
- **Element:** `Destination.menuBar` in `ContentView.detailView`.
- **Current:** Handled in the in-window switch but no sidebar row selects it (it's a popover scene).
- **Expected:** Reachable or removed.
- **HOW IT SHOULD BE:** Remove the `.menuBar` case from the in-window navigation (it's popover-only) to keep the code honest, or add a deliberate in-window preview if intended.

---

## 7. Settings

`SettingsView` with 9 pages (General, Services, Runtimes, Network, Cells, Deploy,
AI, Theme, About). Findings S-1…S-6 are cross-cutting across all pages.

### S-1 — No persistence: every edit is lost · **broken**
- **Element:** All controls (state model).
- **Current:** Edits are lost on re-render because there is no backing model that persists changes.
- **Expected:** Changes persist to disk and survive navigation/restart.
- **HOW IT SHOULD BE:** Back every control with an observable settings model persisted to config (and read back on load). Edits should survive navigation, app restart, and feed the rest of the app (e.g. Tunnel provider, AI key).

### S-2 — Toggles are cosmetic-only · **broken**
- **Element:** Toggle switches (all pages).
- **Current:** Flip a CSS class but have no real switch behavior or effect.
- **Expected:** Real toggles bound to settings that take effect.
- **HOW IT SHOULD BE:** Use native bound toggles whose state persists and changes app behavior; the visual state must reflect the stored value on load.

### S-3 — Inputs have no handlers/validation/typing · **broken**
- **Element:** Text/number/password inputs (all pages).
- **Current:** No handlers, no `type=number`, no validation.
- **Expected:** Typed, validated, bound inputs.
- **HOW IT SHOULD BE:** Inputs should be typed (numeric where appropriate), validated against known ranges, bound to the settings model, and show inline errors for invalid values.

### S-4 — Secret fields stored/shown in cleartext · **wrong**
- **Element:** Deploy token & AI API key fields.
- **Current:** Cleartext, no reveal toggle, no keychain.
- **Expected:** Masked, reveal-on-demand, stored in the keychain.
- **HOW IT SHOULD BE:** Use secure fields with a reveal toggle, store secrets in the macOS Keychain (never plaintext config), and redact them in logs/exports.

### S-5 — Controls are not accessible · **broken**
- **Element:** All controls (accessibility).
- **Current:** No label association, no ARIA/traits, not focusable.
- **Expected:** Properly labeled, focusable, screen-reader-friendly controls.
- **HOW IT SHOULD BE:** Associate each control with its visible `SettingRow` label via `.accessibilityLabel`, ensure focusability, and expose correct traits/values. (See CC-7/CC-8.)

### S-6 — "Services" page shows a single hard-coded detail, not a list · **wrong**
- **Element:** Services nav/page.
- **Current:** Renders one hard-coded service detail instead of the configured services list.
- **Expected:** A list of configured services, each editable.
- **HOW IT SHOULD BE:** Render all configured services; selecting one opens its detail/config. The list should reflect the active project's services, not a fixed example.

### S-7 — Service config schema is PostgreSQL-only · **wrong**
- **Element:** Service config schema.
- **Current:** Hardcoded PostgreSQL fields regardless of the actual service.
- **Expected:** Schema appropriate to each service type.
- **HOW IT SHOULD BE:** Drive the editable fields from a per-service schema (Postgres vs Redis vs MySQL each expose their own keys/ranges/defaults).

### S-8 — Numeric service settings are free-text · **wrong**
- **Element:** Numeric service fields.
- **Current:** Free-text inputs for integer fields with known ranges.
- **Expected:** Numeric inputs with units/range validation.
- **HOW IT SHOULD BE:** Use numeric steppers/inputs with min/max validation and unit hints (e.g. MB), rejecting invalid values before save.

### S-9 — Cells memory/CPU limit fields are free-text · **wrong**
- **Element:** Cells limit fields.
- **Current:** Free-text, no units/validation.
- **Expected:** Validated numeric fields with units.
- **HOW IT SHOULD BE:** Provide validated numeric inputs with explicit units (MB/cores) and sensible bounds, mirroring the isolation backend's capabilities.

### S-10 — Deploy provider select doesn't swap credential fields · **wrong**
- **Element:** Deploy provider select + fields.
- **Current:** Changing the provider doesn't change the credential fields shown.
- **Expected:** Fields adapt to the selected provider.
- **HOW IT SHOULD BE:** Selecting a provider should reveal that provider's credential fields (token vs key/secret vs SSH), validated and stored securely.

### S-11 — AI API key cleartext + non-adaptive fields · **wrong**
- **Element:** AI key & conditional fields.
- **Current:** Cleartext key; fields don't adapt to the chosen provider.
- **Expected:** Secure key + provider-aware fields.
- **HOW IT SHOULD BE:** Mask/keychain the key and show provider-specific fields (endpoint for Ollama, model list per provider), updating as the provider changes.

### S-12 — AI max context size unbounded · **wrong**
- **Element:** AI max context input.
- **Current:** Unbounded free-text, no model-aware limits.
- **Expected:** Bounded to the model's context window.
- **HOW IT SHOULD BE:** Constrain the value to the selected model's max context, validate input, and warn when exceeded.

### S-13 — Theme "System" mode renders as Dark · **wrong**
- **Element:** Theme System mode.
- **Current:** Ignores OS `prefers-color-scheme` and renders Dark.
- **Expected:** Follows the OS appearance.
- **HOW IT SHOULD BE:** "System" should track the OS light/dark setting live and switch when the OS changes.

### S-14 — Theme color edits not persisted, no reset, no WCAG guard · **wrong**
- **Element:** Theme color pickers.
- **Current:** Edits aren't persisted, there's no reset, and no contrast enforcement.
- **Expected:** Persisted custom colors with reset and contrast safeguards.
- **HOW IT SHOULD BE:** Persist custom colors, offer a reset-to-default, and enforce/warn on WCAG contrast (auto-pick a readable foreground for user-chosen semantic colors).

### S-15 — No save/apply/cancel affordance on data pages · **missing**
- **Element:** Data-page action buttons.
- **Current:** No Save/Apply/Cancel.
- **Expected:** Explicit commit/cancel controls.
- **HOW IT SHOULD BE:** Provide Save/Apply and Cancel (or auto-save with a clear "saved" indicator), so users know whether and when their changes take effect.

### S-16 — Network DNS provider is display-only · **missing**
- **Element:** Network DNS provider.
- **Current:** Displayed but not selectable/configurable.
- **Expected:** Selectable/configurable DNS provider.
- **HOW IT SHOULD BE:** Allow choosing/configuring the DNS provider, persisted and applied to `rawenv dns` behavior.

### S-17 — AI autonomy is a binary toggle, not a multi-level picker · **missing**
- **Element:** AI autonomy level.
- **Current:** Only a binary toggle exists.
- **Expected:** A multi-level autonomy picker.
- **HOW IT SHOULD BE:** Provide graduated autonomy levels (e.g. suggest-only → confirm-each → auto-apply) so users can scope what the assistant may do.

### S-18 — Theme Export/Import/Reset & service Save/Validate/Reset are no-ops · **broken**
- **Element:** Theme Export/Import/Reset + service Save/Validate/Reset buttons.
- **Current:** No `onclick` handlers.
- **Expected:** Functional theme and service config actions.
- **HOW IT SHOULD BE:** Export/Import should serialize/load theme JSON; Reset restores defaults; service Save/Validate/Reset should persist, validate against the schema, and revert respectively.

### S-19 — Extension filter chips & buttons inert · **broken**
- **Element:** Extension filter chips/buttons.
- **Current:** No handlers; produce no effect.
- **Expected:** Filter the extension list.
- **HOW IT SHOULD BE:** Chips/buttons should filter the displayed extensions and reflect the active filter state.

### S-20 — Runtimes list static; Install/Remove inert · **broken**
- **Element:** Runtimes list + Install/Remove.
- **Current:** Static list with inert actions.
- **Expected:** Live list with working install/remove.
- **HOW IT SHOULD BE:** Reflect installed runtimes from the store; Install/Remove should call the store (`rawenv add`/remove) with progress and refresh.

### S-21 — About version string inconsistent · **polish**
- **Element:** About version.
- **Current:** Shows 0.1.0 vs 0.2.0 inconsistently across surfaces.
- **Expected:** A single consistent, build-derived version.
- **HOW IT SHOULD BE:** Source the version from one build-time constant/bundle value used everywhere (About, installer done step, menu bar footer).

---

## 8. Installer & Uninstall

First-run installer wizard (`InstallerView` + `InstallerEngine`), in-app uninstall
wizard (`UninstallView`), and the per-runtime install sheet (`InstallFlowVM`).

### IU-1 — Installer swallows errors and always "succeeds" · **broken**
- **Element:** `InstallerEngine` error handling.
- **Current:** Reaches done/success even when the binary download fails (`try?` swallows errors; no error state).
- **Expected:** Failures show an error state with retry.
- **HOW IT SHOULD BE:** Propagate errors into a dedicated `.error(message:)` state, show what failed, and offer Retry (re-attempt the failed step) and Cancel.

### IU-2 — Uninstall `startUninstall()` removes nothing yet reports success · **broken**
- **Element:** Uninstall action.
- **Current:** A 2-second timer flips to `.done` and shows "rawenv has been removed" — zero filesystem/service/PATH operations.
- **Expected:** Actually removes selected items and only reports success on success.
- **HOW IT SHOULD BE:** Invoke the rawenv uninstall logic per selected item (stop services, delete dirs, remove plists, clean PATH), report per-item results, and only show "complete" after verifying removal.

### IU-3 — Uninstall "Cancel" is a no-op · **broken**
- **Element:** `uninstall_cancel`.
- **Current:** Empty closure; does nothing.
- **Expected:** Dismisses/navigates back.
- **HOW IT SHOULD BE:** Cancel navigates back immediately with no residual state; returning later presents a fresh uninstall screen.

### IU-4 — Uninstall UI tests are permanent no-ops · **broken**
- **Element:** Uninstall UI tests.
- **Current:** Navigate to non-existent `about_uninstall`, guard fails, tests return early asserting nothing.
- **Expected:** Tests exercise the real flow.
- **HOW IT SHOULD BE:** Navigate via sidebar `nav_uninstall`, use identifiers that exist, and assert real state changes (checkbox toggling, confirm advancement, cancel).

### IU-5 — Per-runtime "Apply & Retry" loops forever · **broken**
- **Element:** Install sheet Apply & Retry (`InstallFlowVM`).
- **Current:** `applyPortAndRetry()` never consumes the new port; the `name == "SQL Server"` trigger stays true → infinite failure loop.
- **Expected:** Changing the port and retrying succeeds.
- **HOW IT SHOULD BE:** Store the new port, clear the conflict trigger, and re-run with it so retry can succeed, demonstrating real error recovery.

### IU-6 — GUI uninstall shares no code with CLI `rawenv uninstall` · **broken**
- **Element:** GUI vs CLI uninstall.
- **Current:** GUI is purely cosmetic while the CLI performs real removal; the two have diverged.
- **Expected:** Both paths produce identical system state.
- **HOW IT SHOULD BE:** Have the GUI delegate to the CLI or a shared service layer; map per-item selections to CLI capabilities so GUI and CLI behave identically.

### IU-7 — "Verifying SHA256…" is fake · **wrong**
- **Element:** Installer SHA256 step.
- **Current:** Only a 200ms sleep; no checksum computed/compared.
- **Expected:** Real verification or honest labeling.
- **HOW IT SHOULD BE:** Fetch the published digest, compute and compare the downloaded binary's hash, and halt on mismatch; if unimplemented, remove/relabel the step so it doesn't give false assurance.

### IU-8 — "Registering launchd service…" is fake · **wrong**
- **Element:** Installer launchd step.
- **Current:** 200ms sleep; no plist written/loaded.
- **Expected:** Real registration or removal.
- **HOW IT SHOULD BE:** Write a plist to `~/Library/LaunchAgents/`, load it, verify registration; otherwise remove the step.

### IU-9 — "Configuring Seatbelt isolation…" is fake · **wrong**
- **Element:** Installer Seatbelt step.
- **Current:** 200ms sleep; no sandbox profile written.
- **Expected:** Real configuration or removal.
- **HOW IT SHOULD BE:** Write and verify the sandbox profile, or remove the step so users aren't misled about their security posture.

### IU-10 — Welcome "detected" rows are hardcoded · **wrong**
- **Element:** Installer welcome detection rows.
- **Current:** Six static strings; no real OS/arch detection.
- **Expected:** Real detected system values.
- **HOW IT SHOULD BE:** Query actual macOS version, CPU arch, shell, and capabilities and show them so users can verify the installer understands their system.

### IU-11 — Installer done version string hardcoded · **wrong**
- **Element:** Installer done step version.
- **Current:** Hardcoded `rawenv 0.1.0 (macOS arm64)`.
- **Expected:** Read from the installed binary.
- **HOW IT SHOULD BE:** Invoke the installed binary for its version so the displayed string matches `rawenv --version`. (Ties to S-21.)

### IU-12 — Binary-already-exists silently overwritten · **wrong**
- **Element:** Installer existing-binary handling.
- **Current:** Silently overwrites with no version check/backup/prompt; dev-build fallback silently fails yet reports success.
- **Expected:** Detect, inform, and offer update/reinstall/skip.
- **HOW IT SHOULD BE:** Check for an existing binary, show its version, and ask to update/reinstall/cancel, backing up the old binary before overwriting.

### IU-13 — Uninstall item sizes are hardcoded · **wrong**
- **Element:** Uninstall item sizes ("1.2 GB", "180 MB").
- **Current:** Hardcoded literals unrelated to real disk usage.
- **Expected:** Real measured sizes.
- **HOW IT SHOULD BE:** Asynchronously measure actual on-disk usage with a spinner; if measurement fails, omit the size rather than show fake numbers.

### IU-14 — "Launch rawenv →" button is dead code · **missing**
- **Element:** `installer_launch_btn`.
- **Current:** Exists but is unreachable (wrong switch branch) with an empty action.
- **Expected:** A working Launch button on the done step.
- **HOW IT SHOULD BE:** The done step should show a prominent "Launch rawenv →" that calls `markInstalled()` and navigates into the app; remove the unreachable dead code.

### IU-15 — No installer error state / retry · **missing**
- **Element:** Installer error UI.
- **Current:** No `.error` state, message, or retry.
- **Expected:** Error state + retry/cancel.
- **HOW IT SHOULD BE:** Expose an `.error(message:)` state; show which step failed, the description, a Retry (from the failed step), and a Cancel.

### IU-16 — No cancel during uninstall progress · **missing**
- **Element:** Uninstall progress phase.
- **Current:** No cancel once confirmed.
- **Expected:** A cancel during progress.
- **HOW IT SHOULD BE:** Offer a Cancel that halts after the current atomic op, reports removed vs remaining items, and returns to selection with updated state.

### IU-17 — Uninstall checkbox rows lack accessibility ids · **missing**
- **Element:** Uninstall checkbox rows.
- **Current:** No `accessibilityIdentifier`.
- **Expected:** Unique, stable ids per row.
- **HOW IT SHOULD BE:** Add descriptive ids (e.g. `uninstall_item_binary`, `uninstall_item_packages`) matching UI-test expectations.

### IU-18 — Uninstall confirm buttons lack accessibility ids · **missing**
- **Element:** "Go Back" / "Confirm Uninstall".
- **Current:** No identifiers.
- **Expected:** Stable identifiers.
- **HOW IT SHOULD BE:** Add `uninstall_go_back_btn` / `uninstall_confirm_btn`, kept in sync with tests.

### IU-19 — No way to re-run the installer · **missing**
- **Element:** Installer sidebar/Settings entry.
- **Current:** No `nav_installer`; installer is only reachable via the first-run gate.
- **Expected:** A repair/update/reinstall entry point.
- **HOW IT SHOULD BE:** Add a sidebar/Settings entry to re-run the wizard, detecting current install state and offering repair/update/reinstall.

### IU-20 — Uninstall done step has no close/dismiss · **missing**
- **Element:** Uninstall done step.
- **Current:** No Done/Close button; only the sidebar leaves it.
- **Expected:** An explicit dismiss.
- **HOW IT SHOULD BE:** Add a "Done" button that navigates away (or quits / offers reinstall when fully uninstalled), giving clear closure.

---

## 9. State Handling (empty / loading / error — cross-screen)

This section captures the systemic handling of empty/loading/error states. Two
root causes drive most findings: (1) the data layer is non-throwing so every
failure collapses to an empty result, and (2) `.task`-based loading with no
`isLoading` flag makes loading and empty states visually identical.

### ST-1 — `DataRepository` is non-throwing; errors become empty · **broken**
- **Element:** `DataRepository` protocol (all fetch methods).
- **Current:** All methods are non-throwing and return empty arrays/defaults on failure, so a missing binary, CLI crash, timeout, or malformed JSON render identically to a healthy-but-empty project.
- **Expected:** Screens can distinguish "no data" from "fetch failed".
- **HOW IT SHOULD BE:** Make methods throwing or return a `LoadState<T>` (`.loading`/`.empty`/`.loaded(T)`/`.failed(String)`). This single change unlocks real error states across Dashboard, Connections, Deploy, and AI Chat.

### ST-2 — Dashboard service-list empty state · **missing**
- **Element:** Dashboard service list (empty).
- **Current:** Blank space below "0/0" stats.
- **Expected:** An empty state guiding the user to add a service.
- **HOW IT SHOULD BE:** Show icon + "No services yet" + guidance ("Add with `rawenv add postgresql@16` or from Discovery") and a button to Discovery. (See DB-9, ST-23.)

### ST-3 — Dashboard logs empty state · **missing**
- **Element:** Dashboard logs list (empty).
- **Current:** Blank with no explanation.
- **Expected:** "Logs appear once services start."
- **HOW IT SHOULD BE:** Show "No logs yet. Services write to `~/.rawenv/logs` once started." so absence reads as expected, not broken.

### ST-4 — Dashboard loading indicator · **missing**
- **Element:** Dashboard initial fetch.
- **Current:** No loading indicator; blank frame == loading.
- **Expected:** Skeleton/spinner during fetch.
- **HOW IT SHOULD BE:** Show 3 shimmer rows in the service/logs lists for fetches > ~100ms so a slow CLI isn't read as "empty".

### ST-5 — Dashboard error state · **missing**
- **Element:** Dashboard on CLI failure.
- **Current:** Same blank/0 as empty; no error indication.
- **Expected:** A non-blocking error banner with Retry.
- **HOW IT SHOULD BE:** On throw/unreachable CLI, show a dismissible "Couldn't reach the rawenv CLI" banner with Retry (depends on ST-1), without hiding cached data.

### ST-6 — Discovery scan-path failure shows "✓ done" · **wrong**
- **Element:** Scan path result.
- **Current:** Unreadable/permission-denied paths show "✓ done (0 projects)" — identical to a successful empty scan.
- **Expected:** A distinct warning for failed paths.
- **HOW IT SHOULD BE:** Show a ⚠ icon with "permission denied"/"unreadable" so failed scans are distinguishable from genuinely empty directories.

### ST-7 — Projects empty state · **missing**
- **Element:** Project list (empty).
- **Current:** Empty VStack + "0 projects".
- **Expected:** Helpful empty state with actions.
- **HOW IT SHOULD BE:** "No projects found" with tappable "Scan full disk", "+ Add custom path", "check scan paths" that deep-link to the Discovery actions. (See PR-16.)

### ST-8 — Projects filter empty state · **missing**
- **Element:** Project list (filtered to zero).
- **Current:** Silently blank.
- **Expected:** "No results" + clear.
- **HOW IT SHOULD BE:** Show "No projects match '<filter>'." with a Clear button resetting the search.

### ST-9 — Settings pre-load blank body · **polish**
- **Element:** Settings page before `load()`.
- **Current:** Title/subtitle with an empty body (guarded by `if let`), no spinner.
- **Expected:** A loading indicator in the else branch.
- **HOW IT SHOULD BE:** Render `ProgressView("Loading settings…")` while loading — correct even though the hardcoded store makes it near-instant today.

### ST-10 — Settings error state (future persistence) · **missing**
- **Element:** Settings load failure.
- **Current:** Hardcoded, can't fail; no error handling.
- **Expected:** Inline warning when a real read fails.
- **HOW IT SHOULD BE:** Once persisted, a failed read should show "Couldn't load settings — using defaults" rather than silently falling back.

### ST-11 — Deploy code-tab empty state · **missing**
- **Element:** Deploy code tabs (no config).
- **Current:** Blank pane; Copy copies nothing.
- **Expected:** "Generate first" guidance; disabled Copy.
- **HOW IT SHOULD BE:** Show "No deploy config yet — open a project, then Generate" with a Generate button and disabled Copy/Save when empty. (See D-14.)

### ST-12 — Deploy generation error indistinguishable from empty · **wrong**
- **Element:** Deploy code tabs on failure.
- **Current:** Generation failure looks identical to "not generated".
- **Expected:** Distinct error treatment.
- **HOW IT SHOULD BE:** Show a red-tinted banner with the actual CLI stderr and a Retry, separate from the empty state (depends on ST-1).

### ST-13 — Deploy log error banner hardcoded · **wrong**
- **Element:** Deploy log error banner.
- **Current:** Always "Redis failed: port 6379 already in use".
- **Expected:** The real failing step/stderr.
- **HOW IT SHOULD BE:** Derive the headline from the last `isError` log entry. (Duplicate of D-3 — fix once.)

### ST-14 — Deploy code-tab loading indicator · **missing**
- **Element:** Deploy config initial fetch.
- **Current:** No loading indicator.
- **Expected:** Loading skeleton/spinner.
- **HOW IT SHOULD BE:** Show a loading state in the code area so "fetching" isn't read as "not generated".

### ST-15 — AI Chat empty / no-key guidance · **missing**
- **Element:** AI Chat on load with no provider.
- **Current:** Empty thread + a hardcoded proactive banner; no key guidance.
- **Expected:** Guidance to configure a provider.
- **HOW IT SHOULD BE:** Detect provider availability; if none, show "No AI provider configured — add a key in Settings → AI, or start Ollama" with a deep link, and disable input until a provider is available. (See AI-4.)

### ST-16 — AI provider failure rendered as a normal bubble · **wrong**
- **Element:** AI error rendering.
- **Current:** Failures render as ordinary assistant bubbles, only after sending.
- **Expected:** Distinct error treatment with retry.
- **HOW IT SHOULD BE:** Render failures as a distinct error component (error icon/color) with Retry, referencing Settings → AI, so users don't mistake errors for answers.

### ST-17 — AI proactive banner shown without context · **wrong**
- **Element:** Proactive suggestion banner.
- **Current:** A hardcoded PostgreSQL tip always renders even with no history/provider/project.
- **Expected:** Gated on real context + working provider.
- **HOW IT SHOULD BE:** Show it only with real project context and a working provider; otherwise hide it or replace with the configure-a-provider guidance.

### ST-18 — AI history loading indicator · **missing**
- **Element:** AI history initial fetch.
- **Current:** No loading indicator; empty == loading.
- **Expected:** A brief loading skeleton.
- **HOW IT SHOULD BE:** Show a loading state while history loads to avoid a flash of empty content (the TypingIndicator is only for awaiting replies).

### ST-19 — Connections empty state · **missing**
- **Element:** Connections (no data).
- **Current:** Only header/subtitle; `ForEach` renders nothing.
- **Expected:** An explanatory empty state.
- **HOW IT SHOULD BE:** "No connections detected — rawenv reads `DATABASE_URL`, `REDIS_URL`, etc. from your config; add one and rescan." (Duplicate of CT-9.)

### ST-20 — Connections loading indicator · **missing**
- **Element:** Connections initial fetch.
- **Current:** No loading indicator.
- **Expected:** A loading skeleton.
- **HOW IT SHOULD BE:** Show 2–3 shimmer card placeholders while `rawenv connections` parses config, so slowness isn't read as "none".

### ST-21 — Connections error state · **missing**
- **Element:** Connections on CLI failure.
- **Current:** Same blank as "no connections".
- **Expected:** A distinct error banner.
- **HOW IT SHOULD BE:** Show "Couldn't fetch connections from the CLI" with Retry, visually distinct from empty (depends on ST-1).

### ST-22 — Dashboard stats zeros are ambiguous · **wrong**
- **Element:** Stats cards with zero values.
- **Current:** "CPU 0% / Mem 0 MB / Running 0/0" shows both when no services and when the CLI fails.
- **Expected:** Differentiate "zero" from "unavailable".
- **HOW IT SHOULD BE:** Show "—"/hidden on failure or no project; show "Running 0/3" when services exist but are stopped; feed real CPU/Mem or hide those cards. (Relates to DB-2.)

### ST-23 — No reusable `EmptyStateView` component · **missing**
- **Element:** Shared empty-state component.
- **Current:** Each screen lacks or ad-hoc-implements its own empty state.
- **Expected:** One reusable component.
- **HOW IT SHOULD BE:** Build a shared `EmptyStateView` (icon + title + explanation + optional action) used by Dashboard, Projects, Connections, Deploy, and AI Chat, matching the Tunnel screen's tone for consistency.

### ST-24 — Deploy "Start Deploy" lacks a config guard · **wrong**
- **Element:** Start Deploy button.
- **Current:** Offered regardless of whether config exists, allowing deploys with no config.
- **Expected:** Disabled when no config is generated.
- **HOW IT SHOULD BE:** Disable Start Deploy when all three code tabs are empty, with a tooltip "Generate deploy configuration first." (Pairs with the D-1 confirmation gate.)

---

## 10. Cross-Cutting (navigation, theme, resize, accessibility)

Concerns spanning all screens of the macOS SwiftUI app. Per-control no-ops noted
elsewhere (Start All/Stop = DB-1; Deploy/Settings/Uninstall stubs) are not
repeated here.

### CC-1 — Empty-label form controls not associated with their labels · **wrong**
- **Element:** `Picker("")`, `TextField("")`, `SecureField("")`, `ColorPicker("")`, `Slider`, `Toggle("")` across Settings/Uninstall.
- **Current:** Describing text lives in a sibling `SettingRow`/`Text` not programmatically associated, so VoiceOver reads "text field"/"color well"/"slider" with no name.
- **Expected:** Each control announces its purpose.
- **HOW IT SHOULD BE:** Add `.accessibilityLabel(label)` (or non-empty titles) so every control is named for VoiceOver. (Ties to S-5.)

### CC-2 — Only 8 of 10 destinations reachable from the sidebar · **missing**
- **Element:** Sidebar navigation coverage.
- **Current:** `.installer` (first-run gate) and `.menuBar` (separate scene) have no sidebar entry.
- **Expected:** Documented or fully reachable navigation.
- **HOW IT SHOULD BE:** Decide intent: either add deliberate entry points (e.g. a Settings "Re-run installer" — see IU-19) or document these as intentionally out-of-band; the round-trip test should reflect the decision.

### CC-3 — ~10 interactive controls lack accessibility identifiers · **missing**
- **Element:** Deploy Copy/Save/Change-port/Skip/Retry; Connections per-card Copy; AI banner Apply/Dismiss; Uninstall Go Back/Confirm; Settings Runtimes +Install, ColorPickers, many fields; MenuBar toggle pill.
- **Current:** Missing `accessibilityIdentifier`, so they're untestable and "every control has an id" fails.
- **Expected:** Stable ids on every interactive control.
- **HOW IT SHOULD BE:** Add descriptive, stable identifiers to all listed controls and keep them in sync with UI tests.

### CC-4 — No screen-reader labels anywhere · **missing**
- **Element:** Entire view layer.
- **Current:** Zero `accessibilityLabel`/`Value`/`Hint`/`AddTraits`; experience relies on auto-derived labels, which breaks for icon-only/empty controls (the MenuBar toggle is nameless — see MB-5).
- **Expected:** Meaningful VoiceOver labels/roles.
- **HOW IT SHOULD BE:** Add labels/values/traits to icon-only and empty-label controls; give the MenuBar pill a "Toggle <service>" label + toggle trait + value.

### CC-5 — No keyboard shortcuts or default focus · **missing**
- **Element:** App-wide keyboard support.
- **Current:** No `.keyboardShortcut`, `@FocusState`, `defaultFocus`; Tab-focus of non-text controls needs macOS Full Keyboard Access.
- **Expected:** Shortcuts + sensible default focus.
- **HOW IT SHOULD BE:** Add ⌘1…⌘8 for nav and ⌘, for Settings; set `defaultFocus` for primary inputs (AI input, Tunnel port); the sidebar arrow-key navigation already works.

### CC-6 — Fixed semantic accent colors / borderline contrast · **polish**
- **Element:** `accent`/`success`/`warning`/`error` colors.
- **Current:** Fixed (not appearance-adaptive); `accent` as small monospaced text on light `bgPrimary` lands near the WCAG AA 4.5:1 floor; the Theme warning chip uses `.black` text on a user-choosable color.
- **Expected:** Verified contrast in both modes.
- **HOW IT SHOULD BE:** Run a contrast pass; nudge accent for small light-mode text and auto-pick a readable foreground for user-chosen semantic colors.

### CC-7 — MenuBar uses raw SwiftUI colors instead of the theme palette · **polish**
- **Element:** `MenuBarView` colors.
- **Current:** Uses `.green`/`.red`/`.gray`/`Color.accentColor` rather than the adaptive `Color.*` palette; ignores custom theme.
- **Expected:** Consistent with the app palette.
- **HOW IT SHOULD BE:** Use the adaptive `Color.*`/`ThemeManager` colors so the menu bar matches the app and respects custom themes. (Overlaps MB-13.)

### CC-8 — Tunnel create-row doesn't wrap at minimum width · **polish**
- **Element:** Tunnel "Create Tunnel" HStack.
- **Current:** Fixed-width fields in one HStack; tight when the sidebar is widened to 320 at the 900px minimum (no wrap fallback).
- **Expected:** Graceful reflow.
- **HOW IT SHOULD BE:** Use `ViewThatFits`/wrapping so the row reflows to two lines under tight widths.

### CC-9 — Connections DSN truncates (`lineLimit(1)`) · **polish**
- **Element:** Connection string display.
- **Current:** Long DSNs truncate (mitigated by Copy).
- **Expected:** Full value accessible.
- **HOW IT SHOULD BE:** Allow expand/wrap or a tooltip for the full DSN in addition to the Copy button.

### CC-10 — Emoji-in-title buttons announced literally · **polish**
- **Element:** "▶ Start All", "⏹ Stop", "🤖 AI Fix", "↻ Retry", "Use Local ✓".
- **Current:** VoiceOver reads the emoji name aloud.
- **Expected:** Clean spoken labels.
- **HOW IT SHOULD BE:** Use SF Symbols with explicit `accessibilityLabel`s instead of emoji in titles.

### CC-11 — Tunnel port field lacks `onSubmit` · **polish**
- **Element:** `tunnel_port_input`.
- **Current:** Requires a button click; Return doesn't create the tunnel (AI input has `onSubmit`).
- **Expected:** Return submits.
- **HOW IT SHOULD BE:** Add `.onSubmit { createTunnel() }` for keyboard parity with the AI input.

---

## Appendix — Coverage & methodology

- **Screens/areas explored (UI-001…UI-010):** Dashboard, Projects/Discovery, AI
  Chat, Deploy, Connections & Tunnel, Menu Bar, Settings (all 9 pages),
  Installer & Uninstall, cross-cutting (nav/theme/resize/accessibility), and
  state combinations (empty/loading/error). No screens or major controls remain
  unexplored; the Linux (GTK) and Windows (WinUI) GUI ports are flagged for a
  follow-up parity audit (CC §8 of the source doc).
- **Method:** findings were derived by reading shipping source, data layers
  (`DataStore`), unit/UI tests, and the corresponding CLI handlers, compared
  against the canonical design intent in `design/prototype/*`.
- **Severity model:** broken (37) → wrong (47) → missing (62) → polish (18);
  164 findings total across 10 sections.
- **Cross-references:** State Handling (§9) and Cross-Cutting (§10) intentionally
  restate a few per-screen defects where they are best fixed as systemic patterns
  (e.g. ST-1 non-throwing repository; the hardcoded deploy error D-3 ↔ ST-13).
  Fix once, satisfy both.
