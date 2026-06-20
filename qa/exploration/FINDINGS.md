# Exploration Findings — rawenv macOS app (2026-06-18)

Full-app exploration driven via the Accessibility API in the Tart VM (`rawenv-test`), plus
CLI verification. Screenshots in `screenshots/`, cataloged in `manifest.json` (navigation pass)
and `manifest-setup.json` (project setup/install flow). Harnesses: `explore.swift`,
`explore-setup.swift`.

## What WORKS (verified)

- **Navigation** — all 8 sidebar screens render (Dashboard, Discovery, AI Chat, Connections,
  Deploy, Tunnel, Uninstall, Settings) + Settings sub-tabs. (manifest.json steps 1–26)
- **Discovery / scan** — scans `~/Projects`, `~/Developer`, …, `/Volumes/*`; found `demo-node`
  (Node.js) + `rawenv` (Zig). (`102_*`, `103_*`)
- **Detection** — `demo-node` correctly detected as **node 22** + **redis 7 (port 6379)** in the
  GUI setup view; CLI `detect --json` agrees. Nested FrankenPHP/php-8.5 detection also verified
  earlier. (`104_setup_detected.png`)
- **Install + activate (GUI)** — "Set Up Environment" installed **node 22 + redis 7.4.0**;
  setup view showed **"1/1 runtimes · 1/1 services installed"**, redis **"✓ Installed &
  activated"**. (`105_*`, `106_setup_install-complete.png`)
- **Install + activate (CLI)** — `init → add node@22 → add redis@7 → up → status` all succeed
  ("Downloading… Installed node@22.15.0", "Installed redis@7.4.0", DNS `demo-node.test`,
  "No issues detected").

So scan → detect → install → activate genuinely works (CLI and GUI). "Nothing works" is not
accurate for those stages.

## What is BROKEN / missing (the gaps)

### F-RUN (P1) — services install but can't be RUN
- After a successful setup, **redis stays "stopped" and no `redis-server` process exists**
  (`status` → `redis 7.4.0 6379 stopped`; `pgrep redis-server` → none).
- The CLI has **no start/run/serve command**: `up` only *activates runtimes* (re-running `up`
  leaves redis stopped), `down` stops services — asymmetric, nothing starts a service.
- The only start path is the GUI **"Start All"**, which is unreachable because of F-DASH below.
- **Impact:** the core promise — "install what it needs and make it run" — stops at install.
  Verified: redis not running after both GUI setup and CLI `up`.
- **Fix:** add `rawenv up` service-start (or a `rawenv start [svc]`/`service start`) that boots
  the configured services via the service manager (launchd on macOS), and have the GUI setup's
  `up` start them; `status` should then show `running`.
- **Acceptance:** after setup, `rawenv status` shows redis `running` and `pgrep redis-server`
  finds it; GUI shows the service running.

### F-DASH (P2) — Dashboard says "not set up" for a project that IS set up
- With `demo-node` active (sidebar switcher shows "demo-node") and **1/1 runtimes + 1/1 services
  installed & activated**, the Dashboard still shows the empty **"This environment isn't set up
  yet"** state. (`108_dashboard_after-start-all.png` vs `106_setup_install-complete.png`)
- **Impact:** the user can't see or manage (start/stop/log) the services they just set up, and
  the Dashboard's "Start All" has nothing to act on — compounding F-RUN.
- **Fix:** the Dashboard's "is set up" / load logic must recognize a project once its
  runtimes/services are installed+activated (rawenv.toml present), not only some other signal.
- **Acceptance:** after setup, the Dashboard for the active project shows its services (with
  status), not the empty CTA.

### F-A11Y (P2/P3) — primary action buttons aren't activatable by accessibility id
- "View Projects →" (scan-complete banner) has **no accessibility identifier**; "Set Up →"
  (`project_setup_btn_<name>`) has its id on a non-pressable wrapper — so VoiceOver/automation
  can't activate either by id (only by visible text). Navigation worked only after the harness
  switched to text-based `AXButton` presses.
- **Fix:** put `.accessibilityIdentifier(...)` on the actual `Button` (and label the
  scan-complete "View Projects" button); add an accessibility action.
- **Acceptance:** the existing `UIE2ETests`/automation can drive these by id.

## Severity summary
**P1:** F-RUN (services can't be started). **P2:** F-DASH (dashboard doesn't reflect setup),
F-A11Y. The install pipeline is solid; the **run + manage** half of the loop is the gap.

---

## Update — all real projects (mounted `/Volumes/Projects`, 2026-06-18 PM)

Mounted the host's `/Volumes/Projects` into the VM and ran detect + install across **every**
real project, plus drove the GUI setup view. Screenshots `200–211` (`manifest-projects.json`).

### Detection works broadly (read-only `detect` per project)
`gratis → frankenphp 8.5` (R1 nested-stack fix confirmed on the real repo), `gratis-deploy → php 8.1`,
`rahcolours-b2b2c → node 22 + php 8.3 + redis 7 + mysql 8`, `qwik-fullstack → bun 1 + redis 7 + mssql 2022`,
`zelkai-trends → node 22 + python 3.11`, `mcp-for-page-builders → rust`, `Gotas01 → mssql 2022`.
Swift/FoxPro/docs repos correctly detect nothing.

### F-DETECT-INSTALL (P1) — detects stacks it cannot install (RULES §11 contract violation)
Attempting `add` for every detected package: ✅ node, redis, php 8.1, php 8.3, **frankenphp 8.5**, bun.
❌ **rust** → "Unknown package" (detected for mcp, not an installable package);
❌ **mssql** → "Unknown package" (detected for qwik-fullstack, Gotas01);
❌ **mysql@8** → "no prebuilt binary for this OS/architecture" (detected for rahcolours; macOS arm64);
❌ **python@3.11** → resolver only offers 3.12 (version the detector emits can't be installed).
So GUI "Set Up Environment" for those projects fails/partially-fails. **Fix:** for each detectable
runtime/service, either add resolver support (rust, mssql, macOS mysql/mariadb) or stop emitting it
(and map detected versions onto installable ones, e.g. python 3.11→3.12). Verified the GUI surfaces
this gracefully — demo-mysql setup showed a red *"rawenv add mysql@8 failed … no prebuilt binary"*
with Summary "1/1 runtimes · 0/1 services installed" (no crash). (`211_setup_demo-mysql-result.png`)

### F-SCAN-DEPTH (P2) — FIXED this session
The GUI scanner only inspected *direct children* of each root, so a mounted "Projects" volume
nested under the VM share (`/Volumes/My Shared Files/Projects/<repo>`) — and monorepo
`~/Projects/<client>/<app>` — surfaced **0** projects. Fixed `ScannerEngine.scanDirectory` to descend
a bounded depth (`maxScanDepth`) into non-project container dirs, skipping dependency/build noise.
After the fix the scan discovers gratis, rahcolours, qwik-fullstack, mcp, zelkai, gratis-deploy.
Regression test `nestedContainerScannerFindsDeeperRepos` added; full host suite green (642 tests).

### F-DISCOVER-CLI (P2) — `rawenv discover` finds nothing
The CLI `rawenv discover` returned **"No projects found"** in the VM while the GUI `ScannerEngine`
found projects — the CLI discover's scan roots/logic diverge from the GUI scanner. **Fix:** align
the CLI `discover` scan roots/recursion with the GUI scanner (shared logic), or document the gap.

### Positive
Node version picker works (22/20/18/16). Install-failure UX is graceful (red error + partial
summary, no crash). The version-picker + per-service Install controls render correctly
(`204_setup_demo-mysql-version-picker.png`).

---

## Update — full setup run against the REAL projects (2026-06-20, write permission granted)

Ran `init → add → up → status` against each real mounted project (writing real `rawenv.toml`).
**Pitfall caught:** `~/.rawenv/bin/rawenv` had been silently replaced by a stale **Apr-16 1.3 MB**
binary (vs the current 3.3 MB build) — likely the GUI installer clobbering it with an embedded
old CLI (**F-STALE-CLI**, P2). The first run's "unknown package" results were bogus; re-ran after
reinstalling the correct binary.

### Per-project verdict (correct binary)
| Project | Detected → toml | Install result | Verdict |
|---|---|---|---|
| **gratis** | `frankenphp 8.5` (R1 nested-stack fix ✅) | frankenphp installed, **runs PHP 8.5.7** | ✅ works |
| **gratis-deploy** | `php 8.1` | php 8.1.34 installed, "No issues" | ✅ works |
| **rahcolours-b2b2c** | node 22 + php 8.3 + redis 7 + mysql 8 | node+php installed, redis config gen'd; **mysql ✗ no macOS binary** | ⚠️ partial |
| **qwik-fullstack** | bun 1 + redis 7 + mssql 2022 | bun+redis ok; **mssql ✗ Unknown package** | ⚠️ partial |
| **zelkai-trends** | node 22 + python 3.11 | node ok; **python 3.11 ✗ (only 3.12 installable)** | ⚠️ partial |
| **mcp-for-page-builders** | `rust stable` | **rust ✗ Unknown package** — nothing installable | ❌ fails |

### Confirmed end-to-end
- **F-DETECT-INSTALL (P1):** `init` writes the *full* detected stack into `rawenv.toml` — including
  `rust`, `mssql`, `mysql`, `python = "3.11"` — yet `add` cannot install any of them (not in the
  resolver / no macOS binary / version not offered). So projects whose stack includes those can
  only be *partially* set up (or not at all, e.g. mcp). The detection↔installer contract (RULES §11)
  is violated at authoring time. Fix options: (a) add resolver support (rust, mssql, macOS
  mysql/mariadb) — large; (b) map detected versions onto installable ones (python 3.11→3.12) and
  omit/flag truly-unsupported stacks at `init` — smaller.
- **F-RUN (P1):** redis installs + generates a config but stays `stopped`; no CLI start.
- **Runtimes work:** node (`v22.15.0`) and frankenphp (`PHP 8.5.7`) execute from the store; `up`
  activates into a single global `~/.rawenv/bin` (one project active at a time — by design).
- **F-STALE-CLI (P2):** the GUI app overwrote `~/.rawenv/bin/rawenv` with an old embedded binary;
  it should ship/install the current CLI (or never downgrade a newer one).

`rawenv.toml` was written to: gratis, gratis-deploy, rahcolours-b2b2c, qwik-fullstack,
zelkai-trends, mcp-for-page-builders (under the mounted projects volume). Reversible — `rm
rawenv.toml` per project (or `git clean`) to remove.
