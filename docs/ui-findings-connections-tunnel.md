# UI Exploration Findings

Task: **UI-006 — Explore Connections + Tunnel: service dependency map, tunnel providers**

Scope: the **Connections** and **Tunnel** sidebar destinations of the desktop GUI.
The canonical/primary target is the macOS SwiftUI app (`gui/macos`), consistent
with prior UI-00x findings docs. Behavior was derived by reading the shipping
source (`ConnectionsView` + `ConnectionsViewModel`, `TunnelView` + `TunnelVM`),
the data layer (`DataStore`), the unit tests (`ConnectionsVMTests`,
`TunnelVM`-related tests), and comparing against the canonical design intent in
the interactive prototype (`design/prototype/screens-extra.js::renderConnections`
and `design/prototype/screens-deploy.js::renderTunnel`). Cross-platform parity
with the Linux (Vala/GTK) and Windows (WinUI/XAML) ports is noted in §7.

Legend: ✅ works · ⚠️ partial/misleading · ❌ stub or missing · 🔌 CLI/data mismatch · 🎨 prototype-vs-impl gap

---

## 0. How the screens are reached

`ContentView.swift` sidebar (`ContentView.detailView`):

```swift
Label("Connections", systemImage: "link").tag(Destination.connections)   // nav_connections
Label("Tunnel", systemImage: "network").tag(Destination.tunnel)          // nav_tunnel
...
case .connections: ConnectionsView(viewModel: ConnectionsViewModel(repository: appState.repository))
case .tunnel:      TunnelView()        // ⚠️ default init — NOT wired to repository/settings
```

- ✅ Both destinations are present in the sidebar with stable a11y ids
  (`nav_connections`, `nav_tunnel`).
- ⚠️ `TunnelView()` is constructed with its **default initializer**. It is the
  only major destination not handed `appState.repository`. Consequences in §4.

---

## 1. Connections screen — anatomy

`ConnectionsView` (`Views/Connections/ConnectionsView.swift`) is a `ScrollView`
of a left-aligned `VStack`:

1. Title `🔌 Connection Manager`
2. Subtitle `Detected connections from .env and config files`
3. `ForEach(viewModel.connections.indices)` → one `ConnectionCard` each.

Each `ConnectionCard` renders:
- env-var name + a mode badge (Local replacement / Remote (proxied) / Remote),
- optional `Original:` / `Local:` / `Proxy:` monospaced rows,
- the active connection string + a **Copy** button,
- three `ModeButton`s: `Use Remote` / `Use Local ✓` / `Proxy Remote`
  (a11y: `conn_remote_*`, `conn_local_*`, `conn_proxy_*`).

Root id `connections_view`; per-card id `connection_<envVar>`.

---

## 2. Connections — acceptance-criteria results

### AC: "dependency graph displayed for configured project" — 🔌🎨 misframed / not a graph

The acceptance wording ("dependency graph", "service dependency visualization",
"service dependency map") describes the **CLI** `rawenv connections` output and
the `connections` network module's from→to map. The **GUI Connections screen is
not a graph** — it is a connection-string manager (env-var cards with
local/remote/proxy mode switches). There is no node/edge visualization anywhere
in the GUI.

What actually happens (`DataStore.fetchConnections`):

```swift
struct CLIConn: Decodable { let from: String; let to: String }
let conns = try await cli.runJSON(["connections"], as: [CLIConn].self, cwd: projectPath)
return conns.map { Connection(envVar: $0.from, original: $0.to,
                              local: "localhost", mode: "local",
                              badge: "Local", proxy: nil, alternative: nil) }
```

So the GUI **does** consume the CLI's service-dependency map (`from`/`to`
pairs), but flattens every edge into a "Local replacement" connection card:
- `envVar  = from`
- `original = to`
- `local   = "localhost"` (hardcoded — not a real local URL)
- `mode    = "local"`, `proxy = nil`, `alternative = nil` **always**.

Verdict: ✅ data flows from a configured project; ❌ no graph/visualization;
🔌 the "dependency map" semantics are lost in mapping (every entry becomes a
local-mode connection card with a placeholder `localhost` value).

### AC: "empty state when no project configured" — ❌ MISSING

`ConnectionsView` has **no empty-state branch**. The body is just a header +
`ForEach`. When `fetchConnections` returns `[]` (no project, or the CLI errors —
the `catch` returns `[]`), the screen shows only the title and subtitle followed
by blank space. There is no "No connections detected / configure a project"
message, unlike Tunnel's active-tunnels list (which *does* have an empty state,
§4). This AC is **not met** in the GUI.

### Mode switching — ⚠️ cosmetic only

`ConnectionCard.mode` is bound to `viewModel.connectionModes[envVar]` (an
in-memory `[String:String]`). Tapping `Use Remote` / `Use Local` / `Proxy
Remote` updates the badge, the displayed connection string, and the active
button, but is **never persisted** — no CLI call, no `.env`/config write. The
chosen mode is lost on reload and never affects the running environment.

Also: `Proxy Remote` and the `Proxy:` row can never display meaningful data,
because `DataStore` always sets `proxy = nil`. Selecting Proxy falls back to
`connection.original` (`activeConnectionString` returns `connection.proxy ??
connection.original`).

### Copy button — ✅ works (local clipboard)

`Copy` writes `activeConnectionString` to `NSPasteboard.general` and flips the
label to `Copied!` for 1.5s. Pure client-side; no security concern beyond
placing a connection string (possibly containing credentials from `original`)
on the system clipboard.

### Prototype intent that is NOT implemented — 🎨

`renderConnections()` (prototype) shows a richer screen the GUI omits:
- A `MEILISEARCH_URL` card in **proxy** mode with a real `Proxy:` line
  (`localhost:7700 → ms.myapp.com:7700`) — unreachable in the GUI (proxy always nil).
- An `S3_ENDPOINT` card with an `Alternative: MinIO (local S3-compatible)` row
  and an **`Install MinIO`** action button. The `Connection` model carries an
  `alternative` field, but neither the data layer populates it nor the view
  renders it / any install button.

---

## 3. Tunnel screen — anatomy

`TunnelView` (`Views/Tunnel/TunnelView.swift`) is a `ScrollView` / `VStack`:

1. Title `🔗 Tunnel Manager` + subtitle `Expose local services to public URLs`.
2. **Create Tunnel** card: `Port` field, `Provider` picker, `Relay server`
   field, `Create Tunnel` button.
3. **Missing-provider install prompt** (conditional on `installPrompt`).
4. **SSH Command** block (read-only, selectable).
5. **Active Tunnels** list (with empty state).

a11y ids: `tunnel_view`, `tunnel_port_input`, `tunnel_provider_picker`,
`tunnel_relay_input`, `tunnel_create_button`, `tunnel_install_prompt`,
`tunnel_install_btn`, `tunnel_install_cancel`, `tunnel_command`,
`tunnel_entry_<port>`.

---

## 4. Tunnel — acceptance-criteria results

### AC: "provider picker (bore, cloudflared, ngrok, SSH)" — ⚠️ providers differ

The picker (`tunnel_provider_picker`) offers:

```swift
ForEach(["bore", "cloudflared", "ngrok", "rathole"], id: \.self)
```

That is **bore / cloudflared / ngrok / rathole** — **not SSH**. This matches the
prototype's Settings-tab provider `<select>` (`bore (built-in)`, `cloudflared`,
`ngrok`, `rathole`). "SSH" in the AC corresponds instead to the always-visible
**SSH Command** line (§"generated command"), which is the actual tunnel
mechanism regardless of the picker value. So: ✅ a provider picker exists with 4
options; ⚠️ the 4th is `rathole`, not `SSH`, and SSH is not a picker option.

### AC: "port field input and validation" — ❌ no validation

`TextField("3000", text: $viewModel.port)` bound to `TunnelVM.port: String`
(default `"3000"`, width 80). There is **no validation**:
- accepts non-numeric text, empty string, negative or out-of-range values;
- no numeric keypad/formatter, no 1–65535 range check, no error styling;
- the raw string is interpolated straight into `sshCommand`
  (`ssh -R 80:localhost:\(port) \(relayServer)`), so garbage input yields a
  garbage command with no warning.

Verdict: input ✅, validation ❌.

### AC: "missing-tool install prompt when provider not found" — ✅ implemented

`TunnelVM.createTunnel()`:

```swift
guard toolInstalled(provider) else { installError = nil; installPrompt = provider; return }
appendTunnel()
```

- `toolInstalled` defaults to `binaryPath($0) != nil`, scanning
  `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin` for the provider
  binary (GUI apps inherit a minimal `PATH`, hence the explicit dir list).
- When missing, `tunnel_install_prompt` appears: ⚠️ icon, "`<provider>` is not
  installed", an **Install** button and a **Cancel** button.
- `installProvider()` runs `brew install <provider>` off-main-actor; on success
  it clears the prompt and appends the tunnel; on failure it sets
  `installError = "Could not install <p>. Install it manually: brew install <p>"`,
  shown in red. While running, a `ProgressView` replaces the buttons.
- Changing the picker resets the prompt: `provider`'s `didSet` clears
  `installPrompt`/`installError`.

This is the most complete, genuinely-wired control on either screen. ✅
Caveats: macOS/Homebrew-only (no fallback for non-brew systems); the prompt
appears only on **Create**, not proactively when a missing provider is picked.

### AC: "generated command displayed and copyable" — ⚠️ no copy button; provider-agnostic

```swift
public var sshCommand: String { "ssh -R 80:localhost:\(port) \(relayServer)" }
```

- ✅ Displayed in `tunnel_command` as monospaced text with
  `.textSelection(.enabled)`, so it can be selected and copied manually.
- ❌ **No Copy button** — inconsistent with the Connections card (which has one)
  and with the prototype's `📋` copy buttons.
- 🔌 The command is **always the SSH form** and ignores the selected provider.
  Picking `cloudflared`/`ngrok`/`rathole` still shows
  `ssh -R 80:localhost:<port> <relay>`. The displayed command therefore does not
  reflect what `Create Tunnel` would conceptually run for non-bore/ssh providers.
- It also ignores `installPrompt`/installation state — it renders even before any
  provider is installed.

### Create / Active tunnels — ⚠️ simulated

`appendTunnel()` pushes a `TunnelInfo` with a **random** URL
(`bore.pub:<rand>` for bore, else `<provider>.io/<8 hex>`); no real tunnel
process is started. Active rows show `localhost:<port> → <url>`, provider/relay
subtitle, a `StatusDot(isRunning: true)` (always green), and a **Stop** button
that just removes the row. Empty state ✅: "No active tunnels. Create one above."

### Not wired to settings — ⚠️

Because `ContentView` builds `TunnelView()` with defaults, the user's
`network.tunnelProvider` / `network.relayServer` from Settings (`bore` /
`bore.pub`, see `DataStore.fetchSettings`) are **not** used to seed the VM. They
happen to coincide with the hardcoded defaults (`provider = "bore"`,
`relayServer = "bore.pub"`), so the bug is currently invisible but real.

### Prototype intent that is NOT implemented — 🎨

`renderTunnel()` (prototype) is a 3-tab screen (`Active Tunnels` / `Settings` /
`Logs`) far richer than the impl:
- **Active Tunnels** tab: per-service toggles, public URL with copy, live stats
  (latency, uptime, bytes transferred).
- **Settings** tab: provider select, relay server, **custom domain**, plus a
  **Security** section (auth required, IP allowlist, auto-close timer).
- **Logs** tab: request log viewer with Clear/Export and a request/error/blocked
  summary.

The shipped `TunnelView` is a single flat create-form + active list; tabs,
custom domain, security, stats, and logs are all absent.

---

## 5. Security notes

- Connections `Copy` and the Tunnel SSH command place strings that may contain
  credentials (`original` connection URIs) onto the clipboard / screen. Expected
  for a dev tool, but worth flagging.
- `TunnelVM.brewInstall` shells out to `brew install <formula>` where `formula`
  is the picker value. The value is constrained to the 4 hardcoded options (no
  free-text), so there is no injection surface today; if the provider list ever
  becomes user-editable, this would need escaping/validation.

---

## 6. Quick verification matrix (macOS)

| Acceptance criterion | Status | Notes |
|---|---|---|
| Connections: dependency graph for configured project | 🔌 ❌ | Cards, not a graph; CLI map flattened to local-mode cards |
| Connections: empty state when no project | ❌ | No empty-state branch; blank screen |
| Tunnel: provider picker (bore, cloudflared, ngrok, SSH) | ⚠️ | bore/cloudflared/ngrok/**rathole**; SSH is the command, not a picker option |
| Tunnel: port field input + validation | ⚠️ | Input works; **no validation** |
| Tunnel: missing-tool install prompt | ✅ | Wired (brew); macOS-only; on-Create only |
| Tunnel: generated command displayed + copyable | ⚠️ | Selectable text, **no copy button**, provider-agnostic |
| All findings documented | ✅ | This doc |

---

## 7. Cross-platform parity

**Connections**
- **Linux** (`connections_view.vala`): cards like macOS, subtitle "Service
  connection strings with mode switching", mode toggles are **local / proxy /
  tunnel** (different third option than macOS's `remote`). No Copy button, **no
  empty state**, no alternative/Install button. Renders `proxy` row if non-empty.
- **Windows** (`ConnectionsPage.xaml`): present (not deeply inspected here).
- All three render cards, none render a dependency graph; none implement the
  empty state.

**Tunnel** — least consistent surface across ports:
- **macOS**: richest — provider picker (4), port, relay, create, install prompt,
  active list. No copy button, no validation.
- **Linux** (`tunnel_view.vala`): port entry, provider shown as a **static
  label** ("Provider: bore (built-in) · Relay: bore.pub") — no picker, command
  is a **hardcoded** `ssh -R 80:localhost:3000 bore.pub` (ignores the entered
  port), a `Start Tunnel` button, **no install prompt, no active list, no copy,
  no validation**.
- **Windows** (`TunnelPage.xaml`): port `TextBox` (default 3000), "Generate SSH
  Tunnel Command" button, static command text `ssh -R 80:localhost:3000
  bore.pub`. **No provider picker, no install prompt, no validation.**

Net: the SSH-command + bore/bore.pub defaults are the only consistent concepts;
provider selection, install prompts, validation, copy affordance, and empty
states diverge significantly between platforms.

---

## 8. Summary of gaps (prioritized)

1. ❌ **Connections empty state** missing (all platforms) — AC fail.
2. 🔌 **Connections is not a dependency graph/map** — the AC's "service
   dependency visualization" is unmet; CLI map is flattened to local-mode cards
   with a placeholder `localhost` value.
3. ⚠️ **Tunnel port has no validation** — garbage flows into the command.
4. ⚠️ **Tunnel command ignores selected provider** and has **no copy button**.
5. ⚠️ **Connections mode switches are cosmetic** (never persisted).
6. ⚠️ **TunnelView not wired to repository/Settings** (hardcoded defaults).
7. 🎨 Large prototype-vs-impl gaps: proxy/alternative cards (Connections);
   tabs, custom domain, security, stats, logs (Tunnel).
8. ⚠️ Strong **cross-platform divergence** on the Tunnel screen.

Only the **missing-tool install prompt** (macOS) is a fully wired, working
control among the audited features.
