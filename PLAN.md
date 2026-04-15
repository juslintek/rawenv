# rawenv — Final Implementation Plan

**Tagline:** Raw native dev environments. Zero overhead.
**Language:** Zig 0.14 | **License:** MIT | **Domain:** rawenv.com
**Repo:** github.com/rawenv/rawenv

---

## Testing Strategy (TDD — tests first, code second)

### Test Stack
- **Unit tests:** Zig built-in `std.testing` + snapshot testing (TigerBeetle pattern)
- **Integration tests:** Zig `std.process.Child` for CLI subprocess testing
- **TUI tests:** ZigZag headless mode + snapshot comparison
- **GUI tests (ImGui):** `imgui_test_engine` — official Dear ImGui automation framework, supports headless rendering, screenshot capture, simulated input
- **GUI tests (AppKit):** XCTest + Accessibility API for macOS native
- **E2E prototype tests:** Playwright against the HTML prototype (validates UX flows before implementation)
- **CI:** GitHub Actions — `zig build test` on macOS/Linux/Windows

### TDD Flow Per Task
1. Write failing E2E test against prototype (Playwright)
2. Write failing integration test (CLI subprocess)
3. Write failing unit tests (Zig std.testing)
4. Implement minimal code to pass
5. Refactor
6. Screenshot comparison for GUI

---

## Agent Definitions

### Agent 1: `core-engine` — Core Library & CLI
**Scope:** Config parser, project detector, package resolver, store, service manager, shell
**Skills:** Zig systems programming, TOML parsing, process management, cross-platform APIs
**Tools:** fs_read, fs_write, execute_bash, grep, glob, code
**Tests:** Unit tests for each module, integration tests for CLI commands

### Agent 2: `tui-agent` — Terminal UI
**Scope:** ZigZag TUI dashboard, all tab views, keyboard navigation, AI chat panel
**Skills:** ZigZag framework, terminal rendering, event handling
**Tools:** fs_read, fs_write, execute_bash, code
**Tests:** Headless TUI snapshot tests, keyboard input simulation

### Agent 3: `gui-agent` — Native GUI (all platforms)
**Scope:** raylib+zgui (Linux/Windows), AppKit (macOS), Win32+Direct2D (Windows), theme system
**Skills:** ImGui theming, Objective-C interop, Win32 API, raylib
**Tools:** fs_read, fs_write, execute_bash, code
**Tests:** imgui_test_engine for ImGui, XCTest for AppKit, screenshot comparison

### Agent 4: `network-agent` — DNS, Proxy, Tunnel, Connections
**Scope:** dnsmasq/resolved/Acrylic, reverse proxy, bore tunnel, connection manager
**Skills:** Networking, DNS, HTTP, TLS, tunnel protocols
**Tools:** fs_read, fs_write, execute_bash, code
**Tests:** Integration tests with real DNS/HTTP, tunnel connectivity tests

### Agent 5: `isolation-agent` — rawenv Cells
**Scope:** Linux namespaces+Landlock, macOS Seatbelt, Windows AppContainer
**Skills:** OS security APIs, sandboxing, cgroups, process isolation
**Tools:** fs_read, fs_write, execute_bash, code
**Tests:** Verify filesystem/network restrictions per cell, resource limit enforcement

### Agent 6: `deploy-agent` — IaC, Orchestration, Image Building
**Scope:** Terraform/Ansible generation, deployment orchestration, OCI image building
**Skills:** Terraform HCL, Ansible YAML, Containerfile, cloud provider APIs
**Tools:** fs_read, fs_write, execute_bash, code
**Tests:** Generated config validation, dry-run deployment tests

### Agent 7: `ai-agent` — Built-in AI Assistant
**Scope:** LLM provider cascade, project-aware context, proactive suggestions, chat UI
**Skills:** OpenAI-compatible API, prompt engineering, streaming responses
**Tools:** fs_read, fs_write, execute_bash, code, web_fetch
**Tests:** Mock API response tests, context assembly tests, suggestion trigger tests

### Agent 8: `test-agent` — E2E & Quality Assurance
**Scope:** Playwright prototype tests, CI pipeline, cross-platform test matrix
**Skills:** Playwright, GitHub Actions, screenshot comparison, test orchestration
**Tools:** fs_read, fs_write, execute_bash, code, playwright MCP
**Tests:** Maintains the test suite itself, runs full regression

---

## Phase 1: Foundation (MVP — v0.1) — Parallel Agents: core-engine + test-agent

### Task 1: E2E prototype tests [test-agent]
- Set up Playwright against HTML prototype
- Add data-testid attributes to all interactive elements
- Write E2E tests for: installer flow, project discovery, project setup, dashboard navigation, service toggle, settings, theme changes
- These tests define the UX contract — implementation must match
- **Demo:** `npx playwright test` passes all prototype flows

### Task 2: Project scaffold + CI [core-engine]
- GitHub org `rawenv/rawenv`, MIT license
- `build.zig` with cross-compilation targets
- Dependencies: zigzag, zgui, zig-objc, imgui_test_engine
- `src/{core,cli,tui,gui,platform}/` + `tests/`
- GitHub Actions: `zig build test` on macOS/Linux/Windows
- **Demo:** CI green on all 3 platforms

### Task 3: Config parser [core-engine]
- Unit tests first: parse valid TOML, reject invalid, handle edge cases
- Implement rawenv.toml parser
- `rawenv config` command
- **Demo:** `zig build test` passes config tests

### Task 4: Project detector [core-engine]
- Unit tests: detect package.json→Node, composer.json→PHP, .env→connections
- Integration tests: run detector on fixture projects
- Implement scanner for all file types
- `rawenv init` command
- **Demo:** `rawenv init` in test project generates correct rawenv.toml

### Task 5: Package registry + resolver [core-engine]
- Unit tests: semver resolution, platform detection
- Create `rawenv/registry` GitHub repo with initial manifests
- Implement resolver
- **Demo:** `rawenv resolve node@22` returns correct URL

### Task 6: Store + installer [core-engine]
- Integration tests: download, verify SHA256, extract, symlink
- Implement content-addressable store
- `rawenv add`, `rawenv shell`
- **Demo:** `rawenv add node@22 && rawenv run node --version`

### Task 7: Service manager [core-engine]
- Integration tests: start/stop/status per OS
- Implement launchd/systemd/Windows Services integration
- `rawenv up`, `rawenv services ls`
- **Demo:** `rawenv up` starts PostgreSQL, `rawenv services ls` shows running

### Task 8: Shell environment [core-engine]
- Integration tests: PATH injection, env vars
- Implement shell activation for zsh/bash/fish
- **Demo:** `rawenv shell` → `which node` points to .rawenv/bin/

### Task 9: CLI installer + uninstaller [core-engine]
- Integration tests: install script, PATH setup, uninstall cleanup
- `curl -fsSL rawenv.sh/install | sh`
- `rawenv uninstall`
- **Demo:** Fresh install on clean system works

---

## Phase 2: TUI + Network (v0.2) — Parallel Agents: tui-agent + network-agent + isolation-agent

### Task 10: TUI dashboard [tui-agent]
- Snapshot tests for each tab view
- Implement with ZigZag: Services, Logs, Config (view/edit/diff/reset), Resources (table/graph/tree), AI Chat
- Keyboard navigation tests
- **Demo:** `rawenv tui` renders all tabs correctly

### Task 11: rawenv Cells [isolation-agent]
- Unit tests: sandbox profile generation, resource limit enforcement
- Linux: namespaces + cgroups + Landlock
- macOS: Seatbelt sandbox-exec
- Windows: AppContainer + Job Objects
- **Demo:** PostgreSQL in cell can only access its data dir

### Task 12: DNS masking [network-agent]
- Integration tests: resolve .test domains
- macOS: dnsmasq, Linux: systemd-resolved, Windows: Acrylic
- **Demo:** `curl http://myapp.test:3000` works

### Task 13: Reverse proxy + TLS [network-agent]
- Integration tests: proxy routing, self-signed certs
- Built-in HTTP proxy
- **Demo:** `https://myapp.test` works with self-signed cert

### Task 14: Tunneling [network-agent]
- Integration tests: tunnel establishment, public URL access
- bore client + cloudflared integration
- **Demo:** `rawenv tunnel 3000` returns public URL

### Task 15: Connection manager [network-agent]
- Unit tests: parse DATABASE_URL, detect remote vs local
- Detect remote connections, offer local replacement
- **Demo:** Detects AWS RDS in .env, offers local PostgreSQL

---

## Phase 3: GUI + Deploy + AI (v0.3) — Parallel Agents: gui-agent + deploy-agent + ai-agent

### Task 16: GUI — Linux/Windows (raylib + zgui) [gui-agent]
- imgui_test_engine tests for all screens
- Implement: sidebar, dashboard, stats, logs, settings, theme editor with live preview
- Screenshot comparison tests
- **Demo:** GUI launches, all screens render, theme changes live

### Task 17: GUI — macOS (AppKit) [gui-agent]
- XCTest + Accessibility tests
- Menu bar app (NSStatusItem) + main window
- Native dark/light mode
- **Demo:** Click menu bar icon, see services, toggle them

### Task 18: GUI — Windows native (Win32 + Direct2D + DWM) [gui-agent]
- Win32 window with Mica backdrop
- Direct2D custom-drawn controls
- System tray
- **Demo:** Native Windows 11 look with Fluent effects

### Task 19: Theme system [gui-agent]
- Unit tests: TOML theme parse/save, contrast ratio calculation
- Live editor with preview, accessibility warnings
- Import/export themes
- **Demo:** Change accent color, see live preview + contrast warnings

### Task 20: IaC generator [deploy-agent]
- Unit tests: Terraform HCL generation, Ansible YAML generation
- Generate from rawenv.toml for Hetzner/AWS/DO/custom
- **Demo:** `rawenv deploy generate` creates valid terraform/

### Task 21: Deployment orchestrator [deploy-agent]
- Integration tests: dry-run deployment
- `rawenv deploy apply` — runs terraform + provisions
- Error handling with AI-assisted recovery
- **Demo:** Deploy to Hetzner, AI fixes port conflict

### Task 22: Image builder [deploy-agent]
- Unit tests: Containerfile generation
- OCI image + VM image + Dockerfile export
- **Demo:** `rawenv build image` creates working container

### Task 23: AI assistant [ai-agent]
- Unit tests: provider cascade, context assembly, prompt construction
- Chat in TUI + GUI, proactive suggestions
- Groq → Cerebras → Cloudflare → Ollama cascade
- **Demo:** Ask "optimize memory" → gets project-aware answer

### Task 24: Service extensions/plugins [core-engine]
- Unit tests: extension discovery, install, config
- PHP PECL, Node npm globals, Python pip, etc.
- Per-service config editor with docs + validation
- **Demo:** Install PHP redis extension via rawenv

---

## Phase 4: Polish (v1.0) — All agents

### Task 25: Landing page + docs [test-agent]
- rawenv.com on Cloudflare Pages
- Docs: getting started, config ref, CLI ref, deployment guide
- **Demo:** Site live

### Task 26: Full E2E regression suite [test-agent]
- Playwright tests updated to match final implementation
- Cross-platform CI matrix (macOS arm64/x64, Linux x64, Windows x64)
- Performance benchmarks: startup time, memory usage, install speed
- **Demo:** All tests green on all platforms

### Task 27: Release pipeline [test-agent]
- GitHub Releases with cross-compiled binaries
- Install script (curl | sh)
- Homebrew formula, AUR package, winget manifest
- **Demo:** `brew install rawenv` works

---

## Agent Spawn Strategy

### Parallel execution groups:
```
Group A (Phase 1): core-engine + test-agent
  └─ test-agent writes E2E tests while core-engine scaffolds

Group B (Phase 2): tui-agent + network-agent + isolation-agent
  └─ All 3 work independently on different subsystems

Group C (Phase 3): gui-agent + deploy-agent + ai-agent
  └─ All 3 work independently

Group D (Phase 4): All agents converge for integration + polish
```

### Dependencies between agents:
- tui-agent depends on core-engine (needs service manager API)
- gui-agent depends on core-engine (needs service manager API)
- network-agent depends on core-engine (needs config parser)
- deploy-agent depends on core-engine (needs config parser + store)
- ai-agent depends on core-engine (needs project context API)
- isolation-agent is independent (OS-level, no rawenv deps)
- test-agent is independent (tests prototype first, then implementation)
