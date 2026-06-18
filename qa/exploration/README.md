# rawenv macOS App — Exploration Catalog

Full-application exploration driven via the macOS Accessibility (AX) API inside the Tart VM
`rawenv-test`, capturing before/after screenshots of every reachable control and the complete
project setup/install flow.

## Contents
- **`screenshots/`** — sequenced, named PNGs (`<NNN>_<screen>_<action>_<before|after>.png` for the
  nav pass; `<NNN>_<screen>_<action>.png` for the setup flow).
- **`manifest.json`** — navigation pass (steps 001–026): every sidebar screen + dashboard tabs +
  discovery + ai-chat, each with a before/after pair and a context description.
- **`manifest-setup.json`** — project setup/install flow (steps 100–110): scan → View Projects →
  Set Up → detect → install → dashboard, with a context description per shot.
- **`manifest-projects.json`** — all-projects setup pass (steps 200–211): scan of the mounted
  `/Volumes/Projects`, the full Discovered Projects list, and per-project setup (version picker,
  install success/partial/error UX) for the success/unsupported/partial cases.
- **`FINDINGS.md`** — what works vs what's broken (read this first).
- **`explore.swift`** — standalone AX harness for the navigation pass.
- **`explore-setup.swift`** — standalone AX harness for the setup/install flow.
- **`explore-projects.swift`** — standalone AX harness for the all-projects setup pass.

## How it was produced
1. Boot the VM with graphics: `tart run rawenv-test --dir=rawenv:<repo>`.
2. Build the app in-VM: `swift build --build-path /tmp/vmbuild` → `/tmp/vmbuild/debug/Rawenv`.
3. Seed a real project: `~/Projects/demo-node` (package.json node 22 + `.env` REDIS_URL).
4. Run the harnesses over SSH:
   `swift explore.swift /tmp/vmbuild/debug/Rawenv /tmp/out` and
   `swift explore-setup.swift /tmp/vmbuild/debug/Rawenv /tmp/out demo-node`.
   Each launches `Rawenv --ui-testing`, drives controls via AX, and `screencapture`s before/after.
5. Copy `*.png` + `manifest*.json` back to `qa/exploration/`.

## Coverage
- **Navigation (26 steps / 52 shots):** Dashboard, Discovery, AI Chat, Connections, Deploy, Tunnel,
  Uninstall, Settings; dashboard detail tabs (logs/config/connection/cell/backups); start/stop;
  discovery filter + force-rescan + scan-full-disk; ai-chat type + send.
- **Setup/install flow (11 shots):** scan → "View Projects" → Discovered Projects list
  (demo-node Node.js, rawenv Zig) → "Set Up →" → Environment Setup (node 22 + redis 7 detected) →
  "Set Up Environment" → "1/1 runtimes · 1/1 services installed & activated" → Dashboard.

## Key result
The **install pipeline works** (scan → detect → install → activate, both GUI and CLI). The
**run/manage half is broken**: services install but can't be started (no CLI start; `up` doesn't
start services), and the Dashboard shows "not set up" for a project that was just set up — see
`FINDINGS.md` (F-RUN P1, F-DASH P2, F-A11Y P2/P3).

## Notes / limitations
- AX button presses must target the real `AXButton` by text — several action buttons expose their
  `.accessibilityIdentifier` on a non-pressable wrapper (F-A11Y), so id-based presses are no-ops.
- `--ui-testing` does not seed a configured/running project, so cold-launch dashboards show the
  empty state by design.
