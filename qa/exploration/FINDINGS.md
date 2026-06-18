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
