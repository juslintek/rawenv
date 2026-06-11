# UI Findings — State Combinations (empty / loading / loaded / error)

Task: **UI-010 — State combinations: empty/loaded/error/loading for every screen**

Scope: macOS SwiftUI app at `gui/macos`. Every top-level screen reachable from
the sidebar (`ContentView.detailView`) plus the two pre-main gates (Installer,
first-run Projects) was driven through all four canonical states by reading the
shipping source: each `*View.swift`, its `*VM`/ViewModel, the data layer
(`DataStore` + `RawenvCLI`), the engines (`ScannerEngine`, `DeployEngine`,
`InstallFlowVM`, `ProjectSetupVM`), and the AI provider cascade. Behaviour is
cross-checked against the existing per-screen findings docs
(`ui-exploration-findings.md`, `ui-findings-projects.md`,
`ui-settings-exploration.md`, `ui-findings-deploy.md`, `ui-findings-ai-chat.md`,
`ui-findings-connections-tunnel.md`) and the design intent in
`design/prototype/`.

Legend: ✅ clear state · ⚠️ ambiguous/misleading · ❌ missing · 🔌 CLI-degradation

---

## 0. The two architectural facts that decide everything

Before the per-screen matrix, two facts in the data layer explain *why* most
empty/loading/error states look the way they do. Every finding below traces
back to one of these.

### Fact 1 — There is no error channel. Failure == empty.

`DataRepository` (`Protocols/DataRepository.swift`) is **non-throwing**; every
method returns a concrete value, never a `Result` or a `throws`:

```swift
func fetchServices() async -> [Service]
func fetchProjects() async -> [Project]
func fetchConnections() async -> [Connection]
func fetchDeployConfig() async -> DeployConfig
func fetchAIMessages() async -> [AIMessage]
...
```

`DataStore` implements them by swallowing every error:

```swift
public func fetchServices() async -> [Service] {
    do { ... } catch { return [] }     // ← CLI missing? timeout? bad JSON? → []
}
public func fetchConnections() async -> [Connection] {
    do { ... } catch { return [] }
}
public func fetchProjects() async -> [Project] {
    do { ... } catch { return [] }
}
public func fetchDeployConfig() async -> DeployConfig {
    do { ... } catch {}
    return DeployConfig(terraform: "", ansible: "", containerfile: "")
}
```

**Consequence:** for the data-backed screens (Dashboard, Connections, Deploy
configs, AI history, Projects-via-CLI) there is **literally no error state**.
A missing `rawenv` binary, a non-zero exit, a 30s timeout, or malformed JSON all
collapse to the *exact same* render as a healthy-but-empty project. The user is
told "nothing here" when the truth may be "the tool crashed."

### Fact 2 — `load()` runs in `.task`; the pre-load frame *is* the empty frame.

Every screen kicks its fetch from `.task { await viewModel.load() }`. The
ViewModels initialise their `@Published` collections to `[]` / `nil`. SwiftUI
renders **once with the empty initial state**, then re-renders when `load()`
resolves. Because almost no ViewModel exposes an `isLoading` flag for the
initial fetch, **"loading" and "empty" are visually identical** on most screens
— a blank list for the (usually sub-second, but unbounded on a slow/hung CLI)
duration of the fetch.

ViewModels that *do* track progress (and therefore have a real loading state):

| ViewModel | loading flag | drives |
|-----------|--------------|--------|
| `AIChatViewModel` | `isLoading` | `TypingIndicator` while awaiting a reply |
| `ProjectSetupVM` | `isDetecting` | "Detecting services…" + spinner |
| `ProjectsViewModel` | `isScanning` | (set, but the discovery UI uses `ScannerEngine` instead) |
| `ScannerEngine` | `isScanning` / per-path `status` | live scan rows + complete banner |
| `DeployEngine` | `isRunning` / `progress` | deploy progress bar + log stream |
| `InstallFlowVM` | `isInstalling` / `progress` | install sheet progress |
| `TunnelVM` | `installing` | provider-install spinner |

Note: **none** of these covers the *initial data fetch* of Dashboard,
Connections, Settings, Deploy configs, or AI history.

---

## 1. State matrix at a glance

| Screen | Empty | Loading (initial fetch) | Loaded | Error |
|--------|-------|------------------------|--------|-------|
| **Dashboard** | ❌ blank lists, no placeholder; stats show `0/0` | ❌ identical to empty (no spinner) | ✅ stats + service list + logs | ❌ none — CLI fail → empty |
| **Projects · discovery** | ✅ live scan rows, queued/scanning/done | ✅ per-path `⟳ scanning…` icons | ✅ "Scan complete. Found N" banner | ⚠️ unreadable dirs silently skipped; no "scan failed" |
| **Projects · list** | ⚠️ empty `VStack`, only "0 projects" counter | n/a (uses scan engine) | ✅ project rows | ❌ none |
| **Projects · setup** | ✅ "No services detected for this project." | ✅ "Detecting services…" + spinner | ✅ service grid + summary | ✅ `setupVM.error` red text |
| **Projects · install sheet** | n/a | ✅ progress + step checklist | ✅ "✓ installed successfully" | ✅ "✗ Installation failed" + Retry/Change Port/Cancel |
| **Settings** | ⚠️ pre-load: title only, body hidden behind `if let` | ⚠️ identical to empty (no spinner) | ✅ all controls, sensible defaults | ❌ none (defaults are hardcoded, never fail) |
| **Deploy · code tabs** | ⚠️ blank code pane, no "generate first" hint | ⚠️ identical to empty | ✅ rendered IaC + Copy | 🔌 generate fail → blank (same as empty) |
| **Deploy · log tab** | ✅ "▶ Start Deploy" button | ✅ progress bar + streaming log | ✅ ✓/✗ log lines | ⚠️ error banner shown, but **hardcoded text** |
| **AI Chat** | ⚠️ empty thread, but proactive banner always on; no key guidance | ✅ `TypingIndicator` while awaiting | ✅ message bubbles | ⚠️ error returned as an assistant *bubble*, only after send |
| **Tunnel** | ✅ "No active tunnels. Create one above." | ✅ install spinner during brew | ✅ active tunnel cards | ✅ best-in-class: install prompt + manual fallback |
| **Connections** | ❌ blank, only header/subtitle | ⚠️ identical to empty | ✅ connection cards + Copy | ❌ none — CLI fail → empty |

---

## 2. Per-screen detail + HOW IT SHOULD BE

### 2.1 Dashboard — `DashboardView` / `DashboardViewModel`

- **Empty** (`services == []`, `logs == []`): the three `StatsCard`s render
  `CPU 0%`, `Memory 0 MB`, `Running 0/0`; the service `List` and the logs `List`
  are **completely blank** — no row, no caption, no illustration. There is no
  "No services configured — run `rawenv add …`" affordance. (Confirmed in
  `ui-exploration-findings.md` §9.)
- **Loading**: `.task { await viewModel.load() }` — no `isLoading`; the empty
  frame above *is* the loading frame.
- **Loaded** (5+ services): the service `List` scrolls natively, so 5/10/50
  rows lay out fine. Selecting a row only recolors it (cosmetic — see §7 of the
  dashboard doc). Stats sum correctly under test doubles but are `0` in
  production because `services ls --json` carries no cpu/mem.
- **Error**: none. `fetchServices()`/`fetchLogs()` swallow to `[]`.

> **AC: Dashboard with no services → what shows?** Today: blank lists + `0/0`
> cards with no explanation. **AC: Dashboard with 5+ services → layout works?**
> Yes — native `List`, scrolls cleanly, no overflow.
>
> **HOW IT SHOULD BE:**
> - Empty service list → centered empty-state: icon + "No services yet" +
>   "Add a service with `rawenv add postgresql@16` or from the Discovery
>   screen." with a button to Discovery.
> - Empty logs → "No logs yet. Services write to `~/.rawenv/logs` once started."
> - Add a loading skeleton (3 shimmer rows) so a slow/hung CLI doesn't read as
>   "empty project."
> - Distinguish failure from empty: surface a non-blocking banner —
>   "Couldn't reach the rawenv CLI" + Retry — when the fetch throws (requires a
>   throwing repository; see §3).

### 2.2 Projects (Discovery / List / Setup / Install sheet) — `ProjectsView`

This screen is the most state-complete in the app because it is backed by
stateful engines rather than the silent `DataStore`.

- **Discovery — Loading/Empty are explicit and good.** Each scan path shows a
  `queued ○` → `scanning ⟳` → `done ✓ (N projects · cached)` lifecycle via
  `ScannerEngine.PathStatus`. A "Scan complete. Found N projects." banner
  appears on completion. This is the right pattern. ⚠️ Gap: `scanDirectory`
  returns `[]` for an unreadable/permission-denied directory exactly like an
  empty one — a path that *failed* still shows `✓ done (0 projects)`, never a
  "couldn't read" state.
- **List — Empty is weak.** `projectListView` renders `ForEach(filteredProjects)`
  inside a bare `VStack`; with zero discovered projects there is **no
  empty-state message** — just the header, an empty gap, and a "0 projects"
  counter. The *filter* empty case (typed a query that matches nothing) is also
  silent.
- **Setup — fully stated.** ✅ `isDetecting` → "Detecting services…" + spinner;
  ✅ empty → `setup_no_services` "No services detected for this project.";
  ✅ error → `setupVM.error` red line; loaded → service grid + install badges.
- **Install sheet — fully stated.** ✅ installing (progress + ○/✓ step list),
  ✅ complete ("✓ … installed successfully" + store path), ✅ error
  ("✗ Installation failed" + the message + Retry / Change Port / Cancel, with a
  dedicated port-conflict sub-flow). This is the model the rest of the app
  should copy.

> **AC: Projects with no projects found → helpful empty state?** Discovery: yes
> (scan rows + banner). Project **list**: no — blank with only a counter.
>
> **HOW IT SHOULD BE:**
> - Empty project list → "No projects found. Try **Scan full disk**, **+ Add
>   custom path**, or check that your code lives under one of the scan paths."
>   with those actions as buttons (the actions already exist on Discovery).
> - Filtered-to-empty → "No projects match '<filter>'." with a Clear button.
> - Per-path scan failure → distinct `⚠` icon + "permission denied / unreadable"
>   instead of a misleading `✓ 0 projects`.

### 2.3 Settings — `SettingsView` / `SettingsViewModel`

- **Empty/Loading**: `settings` is `AppSettings?`, initially `nil`. Every page
  body is guarded by `if let s = vm.settings` (or `if vm.settings != nil`), so
  **before `load()` resolves each page shows only its title + subtitle and an
  empty body** — no spinner. In practice `DataStore.fetchSettings()` returns a
  fully-populated hardcoded struct synchronously-ish, so this window is tiny,
  but it is a real blank frame.
- **Loaded / defaults**: ✅ all controls populate from `AppSettings`. The
  defaults are sensible and complete: store at `~/.rawenv/store`,
  auto-detect on, `.test` local domain, auto-TLS on, proxy `443`, bore tunnel,
  Seatbelt cells `256MB`/`1` CPU, Hetzner deploy + podman, AI provider cascade
  `groq → cerebras → ollama`, theme `system`/indigo accent. The Theme page has a
  working **Reset to Defaults** (`tm.reset()`).
- **Error**: none — settings are hardcoded in `DataStore`, never read from disk,
  so they cannot fail (and conversely cannot reflect a real `theme.toml`). See
  `ui-settings-exploration.md` for the read-only/no-persistence findings.

> **AC: Settings with defaults → all controls have sensible defaults?** Yes —
> every page has complete, reasonable defaults; Theme has explicit reset.
>
> **HOW IT SHOULD BE:**
> - Wrap the `if let` bodies with a `ProgressView()` in the `else` so a slow load
>   shows "Loading settings…" instead of a bare title.
> - When real persistence lands (currently hardcoded), add a "Couldn't load
>   settings — using defaults" inline warning on read failure.

### 2.4 Deploy — `DeployView` / `DeployViewModel` / `DeployEngine`

- **Code tabs (Terraform/Ansible/Image) — Empty/Loading.** `CodeTab` renders
  `config?.terraform ?? ""`. Before load, or when `deploy generate` fails (🔌
  `fetchDeployConfig` returns empty strings on error), the code pane is **blank
  with a Copy button that copies nothing** — no "Run `rawenv deploy generate` or
  configure a project first" message. Empty and error are identical.
- **Deploy log tab — well stated.** ✅ Empty → "▶ Start Deploy" button (only
  shown when `!isRunning && logs.isEmpty`). ✅ Loading → progress bar
  (`progress`) + streaming `✓/✗` log lines. ✅ Loaded → full log. ⚠️ **Error**:
  when `hasError`, a red banner appears with AI Fix / Change port / Skip / Retry
  — but the banner text is the **hardcoded literal** `"Redis failed: port 6379
  already in use"` regardless of the actual failure. The *real* error from
  `runShell` is appended to `logs` as a red line, so the truth is one place and
  the headline is canned. (See `ui-findings-deploy.md`.)

> **AC: Deploy with no project → clear 'configure first' message?** No — empty
> config tabs are blank, no guidance; the log tab offers Start Deploy regardless.
>
> **HOW IT SHOULD BE:**
> - Empty code tab → "No deploy config yet. This is generated from `rawenv.toml`.
>   Open a project, then **Generate**." + a Generate button; disable Copy/Save
>   when empty.
> - Error banner → render the *actual* failing step + stderr, not a fixed Redis
>   string. Derive the headline from the last `isError` log entry.

### 2.5 AI Chat — `AIChatView` / `AIChatViewModel` / `AIProviderCascade`

- **Empty**: `messages == []` → blank scroll area. But the **proactive
  suggestion banner is always rendered** (a hardcoded PostgreSQL tip) even with
  no history and no configured provider — so the "empty" state looks busy and
  slightly fake. There is **no "add an API key in Settings" guidance** anywhere
  in the empty state.
- **Loading**: ✅ `isLoading` → `TypingIndicator` (three bouncing dots) appended
  below the messages; Send is disabled while input is blank.
- **Loaded**: ✅ user/assistant bubbles, auto-scroll to newest.
- **Error / no key**: ⚠️ the "no API key" condition is **only discoverable by
  sending a message**. With no `GROQ_API_KEY`/`CEREBRAS_API_KEY` and no local
  Ollama, `AIProviderCascade.send` returns the string
  `"Error: all AI providers failed. Set GROQ_API_KEY or CEREBRAS_API_KEY, or run
  Ollama locally."` — which is rendered as a normal **assistant bubble**, not an
  error treatment, and not until after the user types and sends. (See
  `ui-findings-ai-chat.md`.)

> **AC: AI Chat with no API key → clear 'add key in settings' message?** Not
> proactively. The guidance only appears as a chat bubble after a failed send,
> and it points at env vars, not at the Settings → AI page (which has the
> `byom_api_key` field).
>
> **HOW IT SHOULD BE:**
> - On load, detect that no provider is reachable (no keys + Ollama down) and
>   show a banner/empty-state: "No AI provider configured. Add an API key in
>   **Settings → AI**, or start Ollama locally." with a deep-link button.
> - Disable the input + Send (or show the banner inline) until a provider is
>   available, instead of letting the user send into a guaranteed failure.
> - Render provider failures as a distinct error treatment (red, retry), not as
>   an indistinguishable assistant message.
> - Gate or de-emphasise the proactive banner when there's no real context.

### 2.6 Tunnel — `TunnelView` / `TunnelVM` (reference implementation)

This is the **best-handled** screen for states and should be the template.

- **Empty**: ✅ `tunnels.isEmpty` → "No active tunnels. Create one above."
- **No provider installed**: ✅ `createTunnel()` checks `toolInstalled(provider)`;
  if the binary is missing it sets `installPrompt` → a warning card: "<provider>
  is not installed" + "Install it to create a <provider> tunnel." + **Install**
  / **Cancel**.
- **Loading (install)**: ✅ `installing` → `ProgressView` replaces the buttons.
- **Error**: ✅ if `brew install` fails, `installError` →
  "Could not install <provider>. Install it manually: brew install <provider>"
  in red — i.e. *what went wrong* **and** *what to do next*. Changing the
  provider clears the prompt/error (`didSet`).

> **AC: Tunnel with no provider → install guidance shown?** Yes — explicit
> prompt with Install action and a manual-fallback error message. Exemplary.
>
> **HOW IT SHOULD BE:** keep as-is; replicate this pattern (detect → prompt →
> action → manual fallback) on Dashboard, Connections, Deploy, and AI Chat.

### 2.7 Connections — `ConnectionsView` / `ConnectionsViewModel`

- **Empty**: ❌ `connections == []` → only the "🔌 Connection Manager" header
  and "Detected connections from .env and config files" subtitle render; the
  `ForEach` produces nothing and there is **no empty-state** ("No connections
  detected. Add a `DATABASE_URL` to your `.env`…").
- **Loading**: ⚠️ `.task` load, no spinner — identical to empty.
- **Loaded**: ✅ per-connection cards with Original/Local/Proxy rows, a working
  Copy ("Copied!" for 1.5s), and Remote/Local/Proxy mode toggles.
- **Error**: ❌ none — `fetchConnections()` swallows to `[]`. A failed
  `rawenv connections` is indistinguishable from "no connections." (See
  `ui-findings-connections-tunnel.md`.)

> **AC (implied) Connections empty → helpful empty state?** No — blank below the
> header.
>
> **HOW IT SHOULD BE:**
> - Empty → "No connections detected. rawenv reads `DATABASE_URL`, `REDIS_URL`,
>   etc. from your project's `.env`/config. Add one and rescan."
> - Loading skeleton; and a failure banner distinct from empty (needs throwing
>   repository).

### 2.8 Loading indicators — inventory & verdict (AC: "every spinner verified")

| Indicator | Where | Verdict |
|-----------|-------|---------|
| `TypingIndicator` (3 dots) | AI Chat, while `isLoading` | ✅ clear, animated |
| `ProgressView` "Detecting services…" | Project setup | ✅ labeled |
| `ProgressView(value:)` linear | Install sheet | ✅ determinate + step list |
| `ProgressView().controlSize(.small)` | Tunnel install | ✅ replaces buttons |
| Per-path `⟳ scanning…` | Projects discovery | ✅ per-item, clear |
| Deploy progress bar (`GeometryReader`) | Deploy log | ✅ determinate, turns red on error |
| **Initial fetch on Dashboard / Connections / Settings / Deploy configs / AI history** | — | ❌ **no indicator at all** — empty frame doubles as the loading frame |

So every *explicit* spinner is correct and labeled; the systemic gap is the
**absence** of any initial-load indicator on the five `DataStore`-backed views.

---

## 3. Cross-cutting recommendations (root cause first)

1. **Give the repository an error channel.** Make `DataRepository` methods
   `throws` (or return `Result`/a `LoadState<T>` enum). `DataStore`'s
   `catch { return [] }` is the single reason no screen can show "something went
   wrong." This is the highest-leverage fix; it unlocks real error states on
   Dashboard, Connections, Deploy, and AI.
2. **Adopt a four-case `LoadState` per data-backed view**:
   `enum LoadState<T> { case loading, empty, loaded(T), failed(String) }`. Render
   a spinner for `.loading`, an empty-state component for `.empty`, content for
   `.loaded`, and a banner ("what went wrong + Retry") for `.failed`. This
   collapses the empty/loading ambiguity (Fact 2) and the failure/empty
   ambiguity (Fact 1) at once.
3. **One reusable `EmptyStateView`** (icon + title + explanation + primary
   action) used by Dashboard (services, logs), Project list, Connections, and
   Deploy code tabs. Tunnel's empty/prompt copy is the tone to match.
4. **Every error state must answer two questions**: *what went wrong* and *what
   to do next*. Tunnel and the Install sheet already do; copy that. Replace
   Deploy's hardcoded "Redis failed" headline with the real failing step.
5. **AI provider readiness** should be detected on load and surfaced as
   proactive guidance pointing at **Settings → AI**, not as a post-send error
   bubble that mentions only env vars.

---

## 4. AC checklist

- [x] Dashboard with no services → blank lists + `0/0` cards, **no placeholder** (documented; HOW IT SHOULD BE provided).
- [x] Dashboard with 5+ services → native `List`, layout/scroll works.
- [x] Projects with no projects found → discovery has scan rows + banner ✅; **project list has no empty state** (documented).
- [x] Settings with defaults → all controls have complete, sensible defaults ✅; brief pre-load blank frame noted.
- [x] Deploy with no project → **no "configure first" message** on code tabs (documented; HOW IT SHOULD BE provided).
- [x] AI Chat with no API key → **no proactive "add key in Settings" message**; guidance only as a post-send bubble pointing at env vars (documented).
- [x] Tunnel with no provider → install guidance shown ✅ (exemplary; reference pattern).
- [x] Every loading spinner/indicator verified (§2.8 inventory).
- [x] Every error state assessed for "what went wrong + what to do next" (§2; Tunnel/Install pass, Deploy partial, rest missing).
- [x] All findings documented with HOW IT SHOULD BE (per-screen §2 + cross-cutting §3).

---

## 5. Verification

- Documentation-only change; no Swift/Zig source modified, so `zig build` and
  `swift build`/`swift test` baselines are unaffected.
- All code references above were read directly from the shipping source
  (`gui/macos/Sources/Rawenv/{Views,ViewModels,Services,Protocols}`); quoted
  snippets (`catch { return [] }`, the provider-failure string, the hardcoded
  Deploy error, the empty-state strings) are verbatim from those files.
