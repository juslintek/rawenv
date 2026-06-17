# GOAL PROMPT — rawenv macOS GUI: Production-Readiness QA & Remediation

> Feed this to an autonomous agent (with **computer-use**/VM control). It is a
> binding completion contract: keep working until every success criterion is met
> with cited evidence, or a genuine blocker is documented.

---

## Mission

Verify the **rawenv macOS SwiftUI app works flawlessly end-to-end via computer use**.
Build, install, and launch it; **set up rawenv for every real project on this machine
through the GUI**; exercise **every screen, control, and feature**; capture screenshot
evidence; document findings (notes, per-feature reviews, UX feedback); and produce a
**prioritized remediation plan** whose execution makes rawenv production-ready.

Do not simulate. Drive the actual app and the actual CLI against real projects.

## Operating rules (read `RULES.md`, `DESIGN.md`, `AGENTS.md` first)

- **Never run the GUI app or interactive commands from the plain shell** — it hangs.
  Use computer-use / the **test-runner (Tart VM)** to launch and drive the app;
  redirect stdin from `/dev/null` and use timeouts for any CLI; hand sudo/login to the
  user.
- **Never bypass git hooks**; **never mask failures**; **never read `$?` after a pipe**
  (use `set -o pipefail` / redirect-to-file / `${PIPESTATUS[0]}`).
- For any code fix: confirm the branch first, run a **local CodeRabbit + Codex review**
  before committing (fall back if one backend is down), then verify the push landed
  (`git ls-remote` HEAD == local).
- **Detection ↔ installer is one contract** and **GUI shows calm states, not raw
  errors** (RULES §11–§12) — judge findings against these.

## Phase 0 — Setup & baseline

1. Build + install the app and CLI (`bash scripts/install-macos.sh`); confirm
   `rawenv --version` and that the **app-bundled CLI** (`Rawenv.app/Contents/Resources/
   rawenv`) matches source (no stale binary).
2. Launch Rawenv.app via computer-use. Capture the launch screenshot. Confirm no
   crash, no fork-storm, single instance.
3. Enumerate real projects to test (diverse stacks already on disk), at minimum:
   `gratis` (WordPress · FrankenPHP php8.5 · SQLite, nested `gratis-suite/`),
   `mcp-for-page-builders` (Rust), `qwik-fullstack` (Node), `rahcolours-b2b2c` (Node),
   `chargeback-intelligence-mini-api`, `agent-router-swift`. Add more from Discovery.

## Phase 1 — Feature test matrix (exercise EVERY item; screenshot each; record expected vs actual)

Click every control; try valid **and** edge inputs; note flicker, scary errors,
crashes, no-ops, and slow/blocking UI.

- **First-run / Installer**: install flow, progress, error + retry, port-change.
- **Discovery**: scan, **Force rescan all**, **Add custom path**, **Scan full disk**,
  mounted-volume scan (`/Volumes/*`), the **0-projects** state, **View Projects**.
- **Projects / Setup**: per-project **Set Up →**; runtime detection incl. **FrankenPHP
  (php 8.5)** for gratis and language detection for the others; **version pickers**;
  **Set Up Environment** (must install **runtimes + services**, run `up`, show a
  **progress** state + the real **log**, and surface a failed `up`); **Back**; the calm
  "no services detected" copy.
- **Dashboard**: services list (running/stopped), logs, config, per-service tabs; the
  **calm "not set up yet" state + CTA** for an un-initialized project (never a raw
  decode error).
- **Settings** (all tabs): General (store location, launch-at-login), Services,
  **Runtimes** (version **Picker**, per-row progress, **install-log popup**, install +
  remove), Network (proxy port **validation**), Cells (memory/CPU limit validation),
  Deploy (provider + credentials), AI (provider, key reveal, autonomy), Theme, About.
- **AI Chat**, **Connections**, **Deploy** (wizard foundation: targets/triggers/mode),
  **Tunnel**, **Uninstall**.
- **Cross-cutting**: project switcher, **Start All / Stop**, theme switch, window
  resize, every interactive element has an accessibility identifier.

## Phase 2 — Real-world setup (the core)

Through the **GUI**, set up rawenv for **all** discovered projects (not just gratis):
detect → install runtimes + services → activate (`up`) → verify status on the
Dashboard. For each project capture: detected stack vs **actual** stack (inspect the
repo: manifests, Dockerfile `FROM`, compose `build:`, nested dirs, `.env`), install
outcome (success / unknown package / version mismatch), and activation result. Flag
every detection gap and every install failure with a minimal repro.

## Phase 3 — Deliverables (write under `qa/`)

1. **`qa/notes.md`** — chronological observations per screen, with screenshot refs.
2. **`qa/reviews.md`** — per-feature **PASS/FAIL** table with severity (P0–P3) and
   evidence (screenshot/CLI/log refs).
3. **`qa/feedback.md`** — UX issues: confusing states, missing affordances, unclear
   copy, latency, accessibility gaps.
4. **`qa/REMEDIATION.md`** — prioritized plan. Each item: **problem · repro · impact ·
   proposed fix · acceptance criteria**, grouped by production-readiness gate
   (Functionality, Detection/Install, UX/Empty-states, Stability/Perf, Accessibility,
   Packaging/Update). P0 = blocks production.

## Success criteria (binding — verify each with cited evidence)

1. Every screen and control in the matrix is **exercised and documented** with
   screenshot evidence.
2. **Every real project** was set up through the GUI; all detection/install gaps are
   captured with repro.
3. **No crashes**, **no raw error leaks for normal states**, **no no-op/flicker
   actions** observed (or each is filed as a P0/P1 remediation item).
4. The four deliverable docs exist and are complete; **`REMEDIATION.md`** is prioritized
   and actionable, and its P0/P1 closure would make the app production-ready.
5. A final **go / no-go** summary stating remaining P0 count (target: 0) with evidence.

## Loop

For each item: **act** (computer-use) → **observe** (screenshot + state/log) →
**verify** vs expected → **record** (notes/reviews/feedback) → if broken, capture a
repro and add a `REMEDIATION.md` entry with a proposed fix. Iterate until the matrix
and all real projects are fully covered, then synthesize `REMEDIATION.md` + the go/no-go
summary. Only mark the goal complete when the success criteria are met with evidence
you produced this run.
