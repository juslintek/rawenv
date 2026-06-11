# UI Exploration — Projects (Discovery → List → Setup → Install → Done)

**Story:** UI-003 — Explore Projects: discovery, list, setup flow, all project states
**Date:** 2026-06-11
**Surface explored:** `design/prototype/` interactive HTML prototype (the design
source-of-truth for the GUI). Served locally with `python3 -m http.server` and
driven through the in-page `navigate()` router.
**Files behind this flow:**
`design/prototype/screens-projects.js` (all four screens),
`design/prototype/components.js` (modal system + install/migrate/keep sheets),
`design/prototype/app.js` (router + `navigate()`).

> **Scope note.** The Projects flow exists **only in the prototype**. The native
> raylib GUI (`src/gui/screens/`) ships just `dashboard`, `settings`, and
> `menubar` — there is no `projects.zig`/`discover.zig`. So everything below
> documents the *intended* design and the prototype's fidelity to it; it is the
> spec the native GUI still has to implement.

---

## 1. Intended flow map

```
gui-dashboard ─┐
               ▼
  [2] project-scan ──"View Projects →"──▶ [3] project-list ──row / "Set Up →"──▶ [4] project-setup
        │  (discovery: scan locations)          │ (8 discovered projects)              │ (detect + configure)
        │                                        │                                      │
        └──"← Back to installer"──▶ installer-done                                       │
                                                                                  "Apply & Start →"
                                                                                         ▼
                                                                              project-installing
                                                                              (10 animated steps)
                                                                                         │
                                                                              "Open Dashboard →"
                                                                                         ▼
                                                                                  gui-dashboard
```

Breadcrumbs on every screen allow jumping back up the chain
(`Home › Discovery › Projects › utilio Setup › Installing`).

---

## 2. Step-by-step behaviour (observed)

### Step 1 — Discovery scan (`project-scan`)

`renderProjectScan()`. Title: **"🔍 Scanning for projects..."**

**Renders (verified in browser):** 6 scan-location rows in fixed states:

| Location | State | Detail |
|----------|-------|--------|
| `~/Projects/` | ✓ done | (8 projects) · cached |
| `~/Developer/` | ✓ done | (2 projects) · cached |
| `~/Code/` | ✓ done | (0 projects) · cached |
| `/Volumes/Projects/` | ⟳ active | scanning… 4 found so far |
| `~/Desktop/` | ○ pending | queued |
| `~/Documents/` | ○ pending | queued |

Footer: *"14 projects (10 cached, 4 new) · Last full scan: 2 min ago"* — this
communicates the cache model well (cached locations are skipped; only new paths
scanned).

**Interactive elements:**

| Control | Behaviour | Status |
|---------|-----------|--------|
| `View Projects →` (`data-testid=scan-view-projects`) | `navigate('project-list')` | ✅ functional |
| `← Back to installer` | `navigate('installer-done')` | ✅ functional |
| `+ Add custom path` | — | ⚠️ **decorative** (no `onclick`) |
| `Scan full disk` | — | ⚠️ **decorative** |
| `↻ Force rescan all` | — | ⚠️ **decorative** |

**Behaviour gap:** the scan is a *static snapshot* — the `⟳ scanning…` row never
progresses, nothing animates, and the three scan-control buttons do nothing.
**How it SHOULD flow:** the active row should advance through the queued
locations, the "found" counters should tick up, and on completion the active/queued
rows should resolve to ✓ done before auto-advancing (or enabling) "View Projects".
The installer-animation pattern already used on `project-installing` is the model
to copy here.

### Step 2 — Project list (`project-list`)

`renderProjectList()`. Title: **"📁 Discovered Projects"**, subtitle *"Select a
project to set up its environment."*

**Renders (verified in browser):** 8 project rows, each with name, mono path,
stack tags, and dep count:

| Project | Path | Stack | Deps |
|---------|------|-------|------|
| utilio | ~/Projects/GOTAS/utilio | Node.js, Qwik, PostgreSQL, Redis, Meilisearch, SQL Server | 14 deps |
| vialietuva-legacy | ~/Projects/GOTAS/vialietuva-legacy | PHP, Laravel, MySQL, Redis | 8 deps |
| rawenv | ~/Projects/rawenv | Zig | 1 dep |
| mcp-for-page-builders | /Volumes/Projects/mcp-for-page-builders | Rust, Cargo | 2 deps |
| my-saas | ~/Projects/my-saas | Node.js, Next.js, PostgreSQL, Redis, S3 | 10 deps |
| blog | ~/Projects/blog | Ruby, Jekyll | 3 deps |
| data-pipeline | ~/Projects/data-pipeline | Python, PostgreSQL, Redis | 6 deps |
| mobile-app | ~/Developer/mobile-app | Node.js, React Native, Firebase | 5 deps |

Footer: *"14 projects · Monitoring for changes · Cache: 2 min old"* (note the
count says 14 but only 8 rows render — see UI-PROJ-005).

**Interactive elements:**

| Control | Behaviour | Status |
|---------|-----------|--------|
| Project row (whole row) | `navigate('project-setup')` | ✅ navigates, but ⚠️ see below |
| `Set Up →` per row (`data-testid=project-setup-btn`) | no own `onclick`; relies on row-click bubbling | ✅ works via bubble |
| `Filter…` input | no `oninput`/`onkeyup` | ⚠️ **decorative** — typing does not filter |
| `↻ Scan new` | `navigate('project-scan')` | ✅ functional |
| `↻ Full rescan` | — | ⚠️ **decorative** |
| `+ Add project manually` | — | ⚠️ **decorative** |

**Critical behaviour gap (UI-PROJ-001):** **every** row hard-codes
`navigate('project-setup')`, and `project-setup` is hard-coded to **utilio**.
Selecting `blog` (Ruby/Jekyll) or `rawenv` (Zig) lands on utilio's
Node/PHP/Postgres/Redis setup. There is no project-id parameter threaded through
navigation. **How it SHOULD flow:** the selected project's id/path must be passed
to the setup screen, which then renders *that* project's detected stack.

**No details panel:** the acceptance criterion mentions a "details panel," but the
list has none — clicking a row jumps straight to full-screen setup. **How it
SHOULD flow:** either a side/expandable details panel previewing detected
runtimes/services before committing to setup, or this AC should be retired.

### Step 3 — Setup: detect + configure (`project-setup`)

`renderProjectSetup()`. Title: **"⚙️ Environment Setup — utilio"**. This is the
"detect" + "configure" stage combined. Three sections, 7 cards total (verified):

**DETECTED RUNTIMES**
- **💚 Node.js** — badge `Install new`. Source `package.json → engines.node ">=22"`.
  Version `<select>` (22.15.0 / 20.18.0). ~45MB, not installed.
- **🐘 PHP** — badge `Found existing`. Source `composer.json → require.php "^8.4"`.
  Found `/opt/homebrew/bin/php 8.4.6`. Actions: **Keep existing** / **Migrate to rawenv**.

**DETECTED SERVICES**
- **🐘 PostgreSQL** — `Install new`, from `.env DATABASE_URL`. Optimized
  (max_connections=20, shared_buffers=64MB). ~84MB vs ~256MB default · isolated cell.
- **🔴 Redis** — `Found existing`, from `.env REDIS_URL`. Found 7.4.2 (running).
  Actions: Keep existing / Migrate. Hint: *migration saves 32MB → 12MB*.
- **🔍 Meilisearch** — `Replace container`, from `docker-compose.yml`. Native saves ~1.2GB.
- **🗄️ SQL Server** — `Replace container`, from compose. ⚠️ no native macOS → Azure SQL Edge.

**DETECTED CONNECTIONS**
- **☁️ S3_ENDPOINT** — badge `Remote`. Actions: **Keep remote ✓** / **Install MinIO locally**.

**Summary bar:** *"Install 4 · Migrate 0 · Keep 2 existing · Footprint ~462MB (vs
~2.7GB Docker)"* + **Apply & Start →**.

**Interactive elements:**

| Control | Behaviour | Status |
|---------|-----------|--------|
| `Apply & Start →` (`data-testid=setup-apply-btn`) | `navigate('project-installing')` | ✅ functional |
| Keep existing (PHP/Redis) | `showKeepExisting(name, data)` modal | ✅ functional |
| Migrate to rawenv (PHP/Redis) | `showMigrate(name, data)` modal | ✅ functional |
| Install MinIO locally | `showInstallMinIO()` modal | ✅ functional |
| Node version `<select>` | changes selection only | ⚠️ cosmetic (doesn't affect summary or install steps) |
| `Keep remote ✓` | — | ⚠️ **decorative** (no `onclick`) |

**Behaviour gap:** the summary counts ("Install 4 · Keep 2") are static text — they
do **not** react to choosing Keep/Migrate/MinIO in the cards. The badge states
(`Install new`/`Found existing`/`Replace container`/`Remote`) are a good, clear
taxonomy. **How it SHOULD flow:** card decisions should drive the summary totals
and the footprint estimate in real time, and the chosen runtime version should
flow into the install step list.

### Step 4 — Install (`project-installing`) → Done

`renderProjectInstalling()`. Title: **"⚙️ Setting up environment…"**.

**Behaviour (animated, from the inline script):** a `setInterval` (400ms/step)
walks 10 checklist items from `○ pending` → `✓ done` while a progress bar fills
0→100%. Steps: Creating rawenv.toml → Installing Node.js 22.15.0 → PostgreSQL 18.2
→ Meilisearch 1.14 → Azure SQL Edge → Applying optimized configs → Creating
isolation cells → Setting up DNS (utilio.test) → Starting services → Verifying
connections. On completion the disabled "Setting up…" button is replaced with
**Open Dashboard →** (`data-testid=setup-open-dashboard`) → `navigate('gui-dashboard')`.
A `← Back` button (→ `project-setup`) is present throughout.

**Status:** ✅ functional happy-path animation. The `window._setupRan` guard
prevents the interval from double-starting on re-render.

**Behaviour gaps:**
- **Always succeeds.** There is no failure branch — every step always turns green.
  See UI-PROJ-002 for how failure SHOULD flow.
- **Version drift:** the step list says **PostgreSQL 18.2**, but the setup screen
  showed Postgres with no explicit version and the rest of the product elsewhere
  pins Postgres 16 — the installer copy is decoupled from the configured versions
  (cf. the QF-006/QF-015 "no single source of truth for version" theme in
  `qa-findings.md`).
- The Node step says **22.15.0** regardless of what the version `<select>` was set
  to (confirms the select is cosmetic).

---

## 3. Modals / install sheets (`components.js`)

All three are built on a shared `showModal(title, body, actions)` that appends a
`.modal-overlay`; click-outside or the ✕ closes it. The primary action in each
fakes progress (text → "…ing", disabled) then shows a green success state.

| Sheet | Trigger | Content | Primary action |
|-------|---------|---------|----------------|
| **showMigrate** | "Migrate to rawenv" (PHP, Redis) | current install summary + 5 numbered steps (stop → copy data → optimized config → isolation cell → verify/PATH) + green "expected improvement" note | "Migrate to rawenv" → "Migrating…" → "✓ Migrated" |
| **showKeepExisting** | "Keep existing" (PHP, Redis) | current install summary + ✓ what rawenv will do / ✗ what it won't (no cell, no optimization, no auto start/stop) + amber "migrate later" note | "Keep Existing" → "✓ Mapped" → auto-closes |
| **showInstallMinIO** | "Install MinIO locally" (S3) | MinIO explainer + 5 steps (download → configure → bucket → update .env → isolation cell) + console/API URLs | "Install MinIO" → "Installing…" → "✓ Installed" |

These sheets are the most polished part of the flow — clear, honest about
trade-offs (the Keep-existing ✗ list is excellent), and consistent. **Gap:** the
success state is purely local to the button; it does not update the originating
setup card's badge or the summary counts, and it does not persist if you re-open
the sheet.

---

## 4. Error & empty states — the big gap

The acceptance criterion asks for: *no projects, failed detection, missing
binaries, install errors.* **None of these states exist anywhere in the Projects
flow.** Documented here as how they SHOULD flow:

| State | Current | How it SHOULD flow |
|-------|---------|--------------------|
| **No projects discovered** | `project-list` always renders 8 hard-coded rows | Empty state: "No projects found in scanned locations" + CTA to *Add custom path* / *Scan full disk* / *Add project manually* (the buttons that are currently decorative). |
| **Scan in progress / long scan** | static snapshot, no progress | Live progress per location with a cancel affordance; disable "View Projects" until ≥1 result or allow viewing partial results. |
| **Failed detection** (unparseable/conflicting manifests) | n/a — detection always "succeeds" | Per-card warning state (e.g. SQL Server already shows the ⚠️ "no native macOS" pattern — reuse it) and a way to manually pick a runtime/version. Mirror the CLI detector↔resolver gaps catalogued in `qa-findings.md` (bun/mariadb/mssql unsupported, php version mismatch). |
| **Missing binary / unsupported runtime/version** | n/a | Surface the resolver's "Unknown package/version, supported: …" message inline on the card instead of letting Apply proceed. |
| **Install step failure** | every step always turns green | A step turns red with an error line, the progress bar stops, primary button becomes **Retry** / **View log**, and partial progress is reported (which services did start). |
| **DNS needs sudo** (real CLI behaviour) | "Setting up DNS (utilio.test)" always succeeds | Reflect the real CLI behaviour where `.test` DNS needs `sudo` — show a permission prompt/guidance step rather than a silent ✓. |

---

## 5. Findings

| ID | Severity | Finding |
|----|----------|---------|
| **UI-PROJ-001** | 🟠 Major | Project selection is hard-coded: every list row → `navigate('project-setup')`, and setup is hard-coded to **utilio**. No project id/path is threaded through navigation, so the setup screen never reflects the chosen project. |
| **UI-PROJ-002** | 🟠 Major | No error/failure states across the entire flow (no empty list, no failed detection, no missing-binary, no install-step failure). The install animation always succeeds — the unhappy paths the README/CLI actually hit (resolver gaps, sudo DNS) are invisible. |
| **UI-PROJ-003** | 🟡 Minor | Several controls are decorative (no handler): list `Filter…` input, `Full rescan`, `+ Add project manually`; scan `+ Add custom path`, `Scan full disk`, `Force rescan all`; setup `Keep remote ✓`. The empty-state CTAs depend on exactly these. |
| **UI-PROJ-004** | 🟡 Minor | Setup summary counts ("Install 4 · Keep 2"), footprint estimate, and the Node version are static — they don't react to card decisions or the version `<select>`. |
| **UI-PROJ-005** | 🟡 Minor | Count inconsistency: list footer says "14 projects" but 8 rows render; scan footer also says "14 projects". Pick one source of truth. |
| **UI-PROJ-006** | 🟡 Minor | Version drift in install steps: "PostgreSQL 18.2" / "Node.js 22.15.0" are decoupled from the configured/selected versions and from the rest of the product (cf. QF-006/QF-015). |
| **UI-PROJ-007** | ⚪ Trivial | Modal success states are button-local; they don't update the originating card badge/summary and reset on re-open. |
| **UI-PROJ-008** | ⚪ Trivial | No details panel on the list (AC mentions one). Clicking a row jumps straight to full-screen setup. |

> These are **prototype/design** findings (UI fidelity + missing states), distinct
> from the CLI `QF-xxx` findings in `qa-findings.md`. They should be converted to
> stories before the native GUI implements `projects.zig`/`discover.zig`, so the
> error/empty states are designed in from the start rather than retrofitted.

---

## 6. Recommendations (priority order)

1. **Thread project identity through navigation** (UI-PROJ-001). `navigate()`
   needs a payload (project id/path); `renderProjectSetup()` must take it and
   render the selected project's detected stack. This is the prerequisite for the
   flow being more than a single-project demo.
2. **Design the unhappy paths** (UI-PROJ-002): empty discovery, failed detection,
   unsupported runtime/version, and install-step failure with Retry/View-log.
   Reuse the existing ⚠️ card pattern (SQL Server) and the installer animation
   pattern for progress. Align messaging with the real resolver errors.
3. **Wire up the empty-state CTAs** (UI-PROJ-003) — Add custom path, Add manually,
   Scan full disk — since they are the escape hatch when discovery finds nothing.
4. **Make the configure stage reactive** (UI-PROJ-004): card decisions and version
   selection should drive summary totals, footprint, and the install step list.
5. **One source of truth for counts and versions** (UI-PROJ-005/006), mirroring the
   same fix theme already tracked for the CLI.

---

## 7. Acceptance criteria coverage

- [x] **Discovery:** scan screen exercised — 6 scan locations + cache model verified; scan-control buttons found decorative; "View Projects →" / "Back" functional.
- [x] **List view:** 8 projects verified with full data; selection navigates; filter found non-functional; **no details panel** (documented).
- [x] **Setup flow:** detect+configure (7 cards across runtimes/services/connections), install (10-step animation), done (Open Dashboard) all exercised.
- [x] **Error states:** documented as **absent** with how each SHOULD flow (no projects, failed detection, missing binaries, install failure, sudo DNS).
- [x] **Install sheet:** showMigrate, showKeepExisting, showInstallMinIO all exercised and documented.
- [x] **Every step's behavior + how it SHOULD flow** documented (sections 2–4).
