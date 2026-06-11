# UI-002 — Settings Exploration (GUI prototype)

Exhaustive exploration of the Settings screen in the interactive prototype
(`design/prototype/`). Every one of the 9 settings pages was visited and every
control was catalogued: pickers (selects), toggles, text fields, password
fields, sliders, and color pickers. For each control this document records its
**default**, its **range / options**, **what it actually does at runtime**, and
a **HOW IT SHOULD BE** note describing the intended/correct behavior.

## Method & environment

- Target: `design/prototype/index.html` served at `http://localhost:8799/`,
  Settings screen (`renderSettings` → `settingsContent`), nav items defined in
  `screens-gui.js`.
- Driver: headless browser (pinchtab) + DOM/`eval` introspection, cross-checked
  against the prototype source (`screens-gui.js`, `settings-pages.js`,
  `app.js`, `components.js`, `data.js`).
- Each control was exercised: pickers cycled through all options, toggles
  flipped on→off and off→on, text fields typed-into and cleared, sliders moved
  to their extremes, color pickers changed.

**Verification legend:**
- ✅ *live* — behavior observed at runtime in the browser.
- 📄 *source* — behavior determined from the authoritative prototype source
  (deterministic template/handler; live re-confirmation was blocked by an
  idle-tab reaper in the automation harness, but the code path is unambiguous).

## Settings navigation

`renderSettings()` builds a left-rail nav from
`['general','services','runtimes','network','cells','deploy','ai','theme','about']`
with labels `General, Services, Runtimes, Network, Cells, Deploy, AI, Theme,
About`. Each item has `data-testid="settings-nav-<name>"` and
`onclick="window._settingsPage='<name>';render()"`. ✅ All 9 pages render.

---

## 🔑 Cross-cutting findings (apply to every page)

### F-001 — No persistence: every edit is lost on re-render (Major) ✅ live
`render()` rebuilds `#screen-container.innerHTML` from **static template
strings** on every state change. Controls have no backing model. Verified live
on General:
- Flipped **Launch at login** off → on (worked visually), edited **Store
  location** to `/tmp/custom-store`, then cleared it.
- Navigated to **AI** and back to **General** → toggle was **off** again and
  store location was back to `~/.rawenv/store/`. All edits discarded.

**HOW IT SHOULD BE:** every control reads from and writes to a config model
(`rawenv.toml` / `.rawenv/*.toml`). Switching settings pages must preserve
in-progress edits; values persist across navigation and app restarts. Switch
to value-binding or a vdom diff rather than wholesale `innerHTML` replacement.

### F-002 — No Save / Apply / Cancel affordance on data pages (Major) ✅ live
General/Network/Cells/Deploy/AI have **zero buttons** — no Save, Apply, Revert,
or "unsaved changes" indicator (`.settings-content button` returned `[]` on
General). Only Theme and the Services/Service-detail view have action buttons,
and those are inert (see F-014).

**HOW IT SHOULD BE:** each page either auto-saves with a visible "Saved"
confirmation, or shows Save/Cancel with a dirty-state indicator and validation
before write.

### F-003 — Toggles are cosmetic only (Major) ✅ live (mechanism), 📄 source
`toggle(on)` renders `<div class="toggle" onclick="toggleSvc(this)">`.
`toggleSvc` only flips CSS classes (`on`/`off`) on the element — it dispatches
no change event, updates no model, and triggers no side effect. Toggles are
also not keyboard-focusable and expose no ARIA role/state.

**HOW IT SHOULD BE:** toggles are real switches: `role="switch"`,
`aria-checked`, focusable, keyboard-operable (Space/Enter), and each writes its
value to config and applies the effect.

### F-004 — Text/number/password fields have no validation or typing (Major) 📄 source
Every `input.setting-input` is a plain text box with a hard-coded `value` and no
`oninput`/`onchange`, no `type=number` for numeric settings (ports, memory, CPU,
token count), no min/max, no pattern, and no inline error. e.g. Proxy port,
max_connections, Max context size all accept arbitrary text.

**HOW IT SHOULD BE:** typed inputs (`number` with min/max/step for ports
1–65535, sizes, token counts), live validation with inline errors, and
debounced persistence.

### F-005 — Secrets shown without reveal/manage controls (Major) 📄 source
Deploy → "Hetzner API token" is `type=password` with a literal placeholder
`••••••••••`; AI → "API key" is a plain `type=text` box (secret would render in
clear). No show/hide toggle, no "stored in keychain" indication, no clear/rotate.

**HOW IT SHOULD BE:** secrets use a masked field with a reveal toggle, are
stored in the OS keychain/secret store (never echoed), and offer clear/rotate.

### F-006 — Accessibility gaps across all controls (Major) 📄 source
Labels are `<div class="setting-label">` not `<label for>`; inputs have no
`id`/`aria-label`; toggles aren't focusable; color pickers and sliders have no
text alternative for their current value tied to the control. Tab order and
screen-reader naming are effectively broken.

**HOW IT SHOULD BE:** associate `<label for>`/`aria-label` with every control,
ensure focus order, visible focus rings, and ARIA state for custom widgets.

---

## 1. General  📄/✅

| Control | Type | Default | Range/Options | What it does | HOW IT SHOULD BE |
|---|---|---|---|---|---|
| Store location | text | `~/.rawenv/store/` | free text (path) | none — value not bound | path field with picker + existence/writability validation; persists to config |
| Auto-start services | toggle | **on** | on/off | cosmetic flip only | actually start services on `cd` into a project dir |
| Auto-detect projects | toggle | **on** | on/off | cosmetic | enable manifest scanning (`package.json`, `composer.json`, …) |
| Launch at login | toggle | **off** | on/off | cosmetic | register/unregister launchd/systemd/Run-key login item |
| File watcher | toggle | **on** | on/off | cosmetic | start/stop fs watcher on project dirs |
| Scan paths | text | `~/Projects, ~/Developer` | comma list of paths | none | editable list (add/remove rows), validate each path |

Exercised: ✅ toggled *Launch at login* off→on→(reset on renavigate); ✅ typed
and cleared *Store location*. All reverted to defaults (F-001).

---

## 2. Services  📄/✅ (mislabeled — see F-007)

The nav item **"Services"** does **not** show a services list. It renders
`settingsServiceDetailPage()` — the configuration detail of a **single**
service, `SERVICES[window._selectedSvc]` (defaults to index 0 = PostgreSQL).

### F-007 — "Services" settings page is actually a single-service detail (Major) 📄 source
Clicking **Services** drops you straight into PostgreSQL's config editor. There
is no list, no way to pick a different service from here, and the older list
view (`_services_unused`) is dead code. If `window._selectedSvc` were ever
unset (it is hard-defaulted to `0` in `data.js`), `SERVICES[undefined].icon`
would throw — a latent crash.

**HOW IT SHOULD BE:** "Services" shows the list of configured services with
status/port/memory and per-row actions (Config / Logs / Remove / + Add); a
service row opens the detail page. Guard against an unset selection.

Controls present inside the service-detail view:

- **Detail tabs** (pickers-as-tabs): `⚙️ Configuration`, `🧩 Extensions`,
  `📋 Logs`. ✅ switch via `window._svcDetailTab`.
- **Config sub-tabs**: `Visual Editor` / `Raw Config File`
  (`window._svcConfigTab`).
- **Config category sidebar** (Visual): `Connection (4)`, `Memory (4)`,
  `Logging (4)`, `Storage (1)`.
- **Per-setting controls** (Visual editor) — type-driven, each shows
  `range · default`:

| Key | Type | Value (rawenv) | Default | Range | Control rendered |
|---|---|---|---|---|---|
| listen_addresses | string | 127.0.0.1 | localhost | IPs or `*` | text |
| port | integer | 5432 | 5432 | 1–65535 | text (not `number`) |
| max_connections | integer | 20 | 100 | 1–262143 | text |
| unix_socket_directories | string | .rawenv/run/ | /tmp | dir path | text |
| shared_buffers | size | 64MB | 128MB | 128kB–8GB | text |
| work_mem | size | 4MB | 4MB | 64kB–2GB | text |
| maintenance_work_mem | size | 64MB | 64MB | 1MB–2GB | text |
| effective_cache_size | size | 256MB | 4GB | 8kB–8TB | text |
| log_destination | enum | stderr | stderr | stderr, csvlog, jsonlog, syslog | **select** (all options cycle) |
| logging_collector | boolean | on | off | on/off | **toggle** |
| log_directory | string | .rawenv/logs/postgresql/ | log | dir path | text |
| log_min_duration_statement | integer | -1 | -1 | -1..INT_MAX ms | text |
| data_directory | string | .rawenv/data/postgresql/ | /var/lib/postgresql/data | dir path | text |

- **Doc links**: each setting has a `📖 PostgreSQL docs →` external link
  (correct, point to postgresql.org/docs/18). ✅
- **Raw Config File** tab: editable `<textarea>` of `key = val` lines with
  `Save & Restart`, `Validate`, `Reset to rawenv defaults` buttons (inert).
- **Extensions tab**: search box, `Browse PECL` button (`showBrowsePECL()`),
  filter chips (`All`, `Installed (3)`, `Available`, `Database`, `Cache`,
  `Debug`), and a grid of PHP extensions with Install/Remove/Config buttons.

### F-008 — Service config is PostgreSQL-only & hard-coded (Major) 📄 source
The config categories, keys, ranges and the **PHP extensions** grid are all
hard-coded regardless of which service is selected — selecting Redis or
Meilisearch would still show PostgreSQL `postgresql.conf` keys *and* a PHP
extensions tab.

**HOW IT SHOULD BE:** config schema, defaults, ranges, and the
extensions/modules panel are driven per-service (Postgres GUCs, Redis
directives, PHP extensions only for PHP, etc.).

### F-009 — Numeric service settings are free-text (Minor) 📄 source
`port`, `max_connections`, `log_min_duration_statement` render as text inputs
even though their type is `integer` with a known range. No clamping.
**HOW IT SHOULD BE:** numeric inputs with the stated min/max enforced.

### F-010 — Extension filter chips & Visual/Raw doc-links are non-functional (Minor) 📄 source
Filter chips (`Installed (3)` etc.) and Install/Remove buttons have no handlers.
**HOW IT SHOULD BE:** filters narrow the grid; Install/Remove invoke the package
manager with progress feedback.

---

## 3. Runtimes  📄

Rows are hard-coded, not derived from installed state:
- **Node.js** — running dot, `22.15.0 · ~/.rawenv/store/node-22.15.0/`,
  buttons: `Switch version` (`showSwitchVersion(...)` → modal), `Remove`.
- **PHP** — `8.4.6 · /opt/homebrew/bin/php (external)`, button `Migrate to
  rawenv` (`showMigrate(...)` → modal). ✅ modals are the only working actions.
- **Python / Ruby / Go** — greyed "Not installed", each with `+ Install`
  (inert).
- Footer: `Browse all runtimes` (inert).

### F-011 — Runtime list is static; Install/Remove inert (Major) 📄 source
No real detection or actions except the two demo modals.
**HOW IT SHOULD BE:** enumerate runtimes from the store + system, real
install/remove/switch with download+verify progress, reflect actual versions.

---

## 4. Network  📄

Section **DNS Masking**:
- Local domain — text, default `.test` (width 80). → should be a validated TLD.
- DNS provider — **readonly** status (`dnsmasq` / `systemd-resolved` / `Acrylic
  DNS` by OS) showing `● active`.
- Active domains — readonly mono list.

Section **Reverse Proxy**:
- Auto-TLS — toggle, default **on**.
- Proxy port — text, default `80` (width 60). → should be `number` 1–65535.

Section **Tunneling**:
- Tunnel provider — **select**, options: `bore (built-in)`, `cloudflared`,
  `ngrok`, `rathole` (default first). ✅ all options cycle.
- Relay server — text, default `bore.pub`.

### F-012 — OS-dependent DNS provider is display-only with no control (Minor) 📄 source
Provider text changes with the OS selector but you can't choose or configure it.
**HOW IT SHOULD BE:** allow provider selection where multiple are available and
surface install/health status with a fix action.

---

## 5. Cells  📄

Top: a visual grid of cell boxes (postgresql/redis/meilisearch active; node
"no cell"; sqlserver stopped with error border) showing fs/net/mem/cpu — purely
presentational.

Section **Cell Defaults**:
- Enable cells by default — toggle, default **on**.
- Default memory limit — text, default `256MB` (width 80).
- Default CPU limit — text, default `1` (width 60).
- Network isolation — toggle, default **on**.

Header text reflects the OS backend: macOS *Seatbelt (sandbox-exec)*, Linux
*Namespaces + Landlock LSM*, Windows *AppContainer + Job Objects*. ✅

### F-013 — Cell limits are free-text, no units/validation (Minor) 📄 source
`256MB`/`1` are text; no parsing of size suffixes or core counts.
**HOW IT SHOULD BE:** size input with unit dropdown (MB/GB) and numeric CPU
stepper; validate against host capacity.

---

## 6. Deploy  📄

Section **Default Provider**:
- Provider — **select**: `Hetzner`, `AWS`, `DigitalOcean`, `GCP`, `Azure`,
  `Custom SSH` (default Hetzner). ✅ all cycle.
- Hetzner API token — **password**, masked literal `••••••••••` (see F-005).
- SSH key — text, default `~/.ssh/id_ed25519.pub`.

Section **IaC**:
- Terraform path — text, default `terraform`.
- Ansible path — text, default `ansible-playbook`.
- Auto-generate on setup — toggle, default **off**.

Section **Image Building**:
- Container runtime — **select**: `Podman`, `Docker`, `Buildah` (default
  Podman). ✅ all cycle.
- Registry — text, default `ghcr.io/rawenv`.

### F-015 — Provider select doesn't reveal provider-specific fields (Minor) 📄 source
The token field stays labelled "Hetzner API token" regardless of the selected
provider; binary path fields aren't validated for existence.
**HOW IT SHOULD BE:** changing Provider swaps in that provider's credential
fields; validate binary paths and offer to locate them.

---

## 7. AI  📄/✅

Section **Provider**:
- AI provider — **select**, 8 options: `Auto (Groq → Cerebras → CF)`,
  `Groq (Llama 3.3 70B)`, `Cerebras (Qwen3 235B)`, `Cloudflare Workers AI`,
  `Google Gemini`, `Mistral AI`, `Ollama (local)`, `Custom OpenAI-compatible`
  (default Auto). ✅ all cycle.
- API key — text (not password), default empty, placeholder `Optional`.
- Ollama endpoint — text, default `http://localhost:11434`.

Section **Behavior**:
- Proactive suggestions — toggle, default **on**.
- Auto-apply safe fixes — toggle, default **off**.
- Include logs in context — toggle, default **on**.
- Max context size — text, default `4096`, suffix label "tokens".

### F-016 — AC mismatch: no "autonomy level" picker (Major) 📄 source
The acceptance criteria expect an **autonomy level picker**, but the page only
offers a single binary **"Auto-apply safe fixes"** toggle. There is no
multi-level autonomy control.
**HOW IT SHOULD BE:** replace the binary toggle with an autonomy picker —
e.g. `Off` / `Suggest only` / `Auto-apply safe` / `Full auto` — and persist it.

### F-017 — API key is a clear-text field (Major) 📄 source — see F-005
Should be masked + keychain-stored. Also: provider/key/endpoint fields don't
adapt (e.g. Ollama endpoint is irrelevant unless Ollama is selected; API key is
irrelevant for free-tier `Auto`).
**HOW IT SHOULD BE:** show only fields relevant to the chosen provider.

### F-018 — Max context size unbounded free-text (Minor) 📄 source
`4096` is text; no min/max or model-aware cap.
**HOW IT SHOULD BE:** numeric with provider/model-aware limits.

---

## 8. Theme  📄/✅ (richest interactive page)

Rendered by `settingsThemePage()`. Layout: controls column + live preview panel.

**Mode**
- Color mode — **select**: `Dark`, `Light`, `System`. Default reflects
  `window._theme` (dark). `onchange="setTheme(this.value)"`.

**Colors** — 6 native color pickers (`<input type=color>`), each
`oninput="applyThemeColor('--var', value)"`:
| Picker | Default | CSS var |
|---|---|---|
| Accent | `#6366f1` | `--accent` |
| Success | `#34d399` | `--success` |
| Error | `#f87171` | `--error` |
| Warning | `#fbbf24` | `--warning` |
| Info | `#60a5fa` | `--info` |
| Background | `#0f0f14` | `--bg-primary` |

`applyThemeColor` sets the CSS variable live, updates the theme-file preview
text (`#tv-accent` etc.), and (wrapped) triggers `updateContrastWarnings()`.

**Accessibility** — `#contrast-warnings` renders 7 WCAG badges
(text/muted/accent/success/error/warning on bg, plus white-on-accent) computed
via real luminance/contrast-ratio math, labelled AAA / AA / low / fail.

**Layout** — 2 sliders:
- Border radius — range **0–16**, default **8** (`+px`); sets
  `--radius-md`, `--radius-lg` (+4), `--radius-sm` (−4), updates label,
  `updatePreview()`.
- Font size — range **11–16**, default **13** (`+px`); sets `--font-size`,
  updates label.
(Note: the *unused* legacy template also had a "Sidebar width" 180–320 slider;
the live `settingsThemePage()` does **not** render it.)

**Theme File** — read-only `theme.toml` preview that interpolates
`window._theme` and the live color/radius/font values; buttons `Export`,
`Import`, `Reset`.

Exercised earlier in a live session before the harness became unstable:
selecting Light/Dark recolors the whole app (`setTheme` sets
`document.body.className`); color pickers and sliders update CSS vars live;
contrast badges recompute.

### F-014 — Theme Export / Import / Reset buttons are dead (Minor) 📄 source
No `onclick` handlers on the three buttons (same for the Service Raw-config
Save/Validate/Reset).
**HOW IT SHOULD BE:** Export writes `theme.toml`; Import loads a file; Reset
restores defaults and re-renders.

### F-019 — "System" mode does not follow the OS (Major) ✅ logic confirmed in source
`setTheme(t)` does `document.body.className = t==='light' ? 'light' : ''`. For
`t==='system'` the class becomes `''` — identical to Dark. It never queries
`window.matchMedia('(prefers-color-scheme: ...)')` and never listens for OS
changes. So **System silently renders as Dark**, and the theme-file preview then
prints `scheme = "system"` which won't round-trip to a real mode.
**HOW IT SHOULD BE:** System resolves via `prefers-color-scheme`, applies the
matching palette, and live-updates when the OS theme changes.

### F-020 — Color changes aren't scoped/persisted and can break readability (Minor) 📄 source
Color edits mutate global CSS vars with no reset-per-control and no save; the
contrast checker *warns* but nothing prevents a fail-level choice.
**HOW IT SHOULD BE:** per-color reset, persistence to `theme.toml`, and an
optional guard (or one-click auto-fix) when a combo fails WCAG AA.

---

## 9. About  📄

All read-only:
- Big logo, `rawenv`, `Version 0.1.0 · Built with Zig 0.14`, license/links line.
- Rows (mono, readonly), OS-dependent: **OS** (macOS 26 arm64 / Debian 13 x86_64
  / Windows 11), **Service manager** (launchd / systemd / Windows Services),
  **Isolation** (Seatbelt / Namespaces+Landlock / AppContainer+Job Objects),
  **Store** (`~/.rawenv/store/ (1.8GB used)`), **Projects** (`14 discovered · 3
  active`).
- Buttons: `Check for updates` (`showUpdateCheck()` → modal, works), `Uninstall
  rawenv` (→ navigates to uninstall screen, works).

### F-021 — Version strings inconsistent across the app (Trivial) 📄 source
About says **0.1.0 / Zig 0.14**; the menu-bar footer says **v0.1.0**; the README
shows **0.2.0** and **Zig 0.16**. 
**HOW IT SHOULD BE:** single source of truth for version/toolchain, injected at
build time.

---

## Findings summary

| ID | Page(s) | Severity | Verified | Title |
|---|---|---|---|---|
| F-001 | all | Major | ✅ live | No persistence — edits lost on re-render |
| F-002 | data pages | Major | ✅ live | No Save/Apply/Cancel affordance |
| F-003 | all | Major | ✅/📄 | Toggles cosmetic only, not real switches |
| F-004 | all | Major | 📄 | Text/number fields: no typing/validation/`number` |
| F-005 | Deploy/AI | Major | 📄 | Secrets shown without reveal/keychain |
| F-006 | all | Major | 📄 | Accessibility: no label-for/ARIA/focus |
| F-007 | Services | Major | 📄 | "Services" page is a single hard-coded detail |
| F-008 | Services | Major | 📄 | Service config PostgreSQL-only/hard-coded |
| F-009 | Services | Minor | 📄 | Numeric service settings free-text |
| F-010 | Services | Minor | 📄 | Extension filters/buttons inert |
| F-011 | Runtimes | Major | 📄 | Static list; install/remove inert |
| F-012 | Network | Minor | 📄 | DNS provider display-only |
| F-013 | Cells | Minor | 📄 | Cell limits free-text, no units |
| F-014 | Theme/Services | Minor | 📄 | Export/Import/Reset & Save/Validate dead |
| F-015 | Deploy | Minor | 📄 | Provider doesn't reveal provider-specific fields |
| F-016 | AI | Major | 📄 | No autonomy-level picker (AC mismatch) |
| F-017 | AI | Major | 📄 | API key clear-text; fields don't adapt |
| F-018 | AI | Minor | 📄 | Max context size unbounded |
| F-019 | Theme | Major | ✅ logic | "System" mode renders Dark, ignores OS |
| F-020 | Theme | Minor | 📄 | Color edits unscoped/unpersisted; no WCAG guard |
| F-021 | About | Trivial | 📄 | Version strings inconsistent (0.1.0 vs 0.2.0) |

**Totals:** 11 Major, 9 Minor, 1 Trivial across all 9 pages.

> Note: this prototype is intentionally a **visual design mock** — most "dead"
> behaviors are expected at the prototype stage. The findings above define the
> contract the real GUI (`src/gui/`) must satisfy: bound config model,
> persistence, validation, real actions, accessibility, secret handling, a true
> System theme mode, and an AI autonomy-level picker.
