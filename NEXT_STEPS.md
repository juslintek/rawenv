# rawenv — Next Steps (Prototype → Working Product)

Each step maps to a prototype screen. The acceptance criteria is:
**the real CLI/TUI must behave identically to the prototype.**

---

## Sprint 1: Core CLI (rawenv init → rawenv up → rawenv status)

### Step 1: rawenv init — Project Detector (Prototype: "4. Setup" screen)
**What prototype shows:** Scans project dir, finds package.json/composer.json/.env/docker-compose.yml, detects runtimes and services, shows what to install vs what exists, generates rawenv.toml.
**Implementation:**
- src/core/detector.zig — scan current dir for manifest files
- Parse package.json engines.node, composer.json require.php
- Parse .env for DATABASE_URL, REDIS_URL (connection detection)
- Parse docker-compose.yml for service images
- Generate rawenv.toml with detected stack
**Acceptance test:** `cd ~/Projects/GOTAS/utilio && rawenv init` produces correct rawenv.toml

### Step 2: rawenv add — Package Store (Prototype: "4. Setup" installing animation)
**What prototype shows:** Downloads Node.js, PostgreSQL, Redis etc. with progress bars.
**Implementation:**
- src/core/store.zig — HTTP download with progress, SHA256 verify, extract
- src/core/resolver.zig — resolve "node@22" to download URL from registry
- Registry: JSON files in rawenv/registry GitHub repo (start with Node, PostgreSQL, Redis)
- Store at ~/.rawenv/store/{name}-{version}/
**Acceptance test:** `rawenv add node@22` downloads, extracts, `~/.rawenv/store/node-22.15.0/bin/node --version` works

### Step 3: rawenv up — Service Manager (Prototype: Dashboard sidebar "Start All")
**What prototype shows:** Starts all services, shows running status with PIDs and ports.
**Implementation:**
- src/core/service.zig — read rawenv.toml, start each service as background process
- macOS: launchd plist generation + launchctl load
- Per-service data dirs: .rawenv/data/{service}/
- Auto-configure: postgres initdb, redis default config
**Acceptance test:** `rawenv up` starts PostgreSQL on :5432, `psql -h localhost -p 5432` connects

### Step 4: rawenv status / rawenv services ls (Prototype: Dashboard service list)
**What prototype shows:** Service name, status dot, port, PID, CPU, memory, uptime.
**Implementation:**
- Query launchd for service status
- Read /proc or ps for CPU/memory
- Format as table
**Acceptance test:** `rawenv services ls` shows running services with correct ports

### Step 5: rawenv shell (Prototype: not directly shown but referenced)
**What prototype shows:** Isolated shell with PATH pointing to .rawenv/bin/
**Implementation:**
- Prepend .rawenv/bin/ to PATH
- Set DATABASE_URL, REDIS_URL etc from rawenv.toml
- Spawn $SHELL
**Acceptance test:** `rawenv shell` → `which node` → `.rawenv/bin/node`

---

## Sprint 2: TUI Dashboard (rawenv tui)

### Step 6: Services tab (Prototype: TUI "Services" tab)
**What prototype shows:** Table with status dots, service name, version, port, PID, CPU, MEM, uptime. Selected row highlighted. j/k navigation.
**Implementation:** Wire src/tui/views/services.zig to real service manager data
**Acceptance test:** `rawenv tui` shows actual running services, j/k navigates

### Step 7: Logs tab (Prototype: TUI "Logs" tab)
**What prototype shows:** Scrollable log viewer with timestamps, level coloring, filter/search.
**Implementation:** Read service log files, tail -f style, level detection
**Acceptance test:** PostgreSQL logs appear in real-time

### Step 8: Config tab (Prototype: TUI "Config" tab with 4 modes)
**What prototype shows:** View/edit/diff/reset modes for service config.
**Implementation:** Read/write actual config files, diff against defaults
**Acceptance test:** Edit postgresql.conf via TUI, restart service, changes apply

### Step 9: Resources tab (Prototype: TUI "Resources" tab with 3 modes)
**What prototype shows:** Table/graph/tree views of CPU, memory, disk per service.
**Implementation:** Read real process stats
**Acceptance test:** CPU/memory numbers match `ps aux`

### Step 10: AI Chat tab (Prototype: TUI "AI Chat" tab)
**What prototype shows:** Chat with Groq, project-aware context, proactive suggestions.
**Implementation:** Wire src/ai/ to real HTTP calls, build context from running services
**Acceptance test:** Type "optimize memory" → get real response about actual services

---

## Sprint 3: Network + Isolation

### Step 11: DNS masking (Prototype: Settings → Network)
### Step 12: Reverse proxy (Prototype: Settings → Network)
### Step 13: Tunneling (Prototype: Tunnel screen)
### Step 14: Connection manager (Prototype: Connections screen)
### Step 15: rawenv Cells (Prototype: Dashboard → Cell tab)

---

## Sprint 4: GUI + Deploy + Polish

### Step 16: GUI with raylib+zgui (Prototype: Dashboard screen)
### Step 17: macOS AppKit menu bar (Prototype: Menu Bar screen)
### Step 18: Deploy (Prototype: Deploy screen)
### Step 19: Visual installer (Prototype: Installer screens)
### Step 20: Project discovery (Prototype: Discover + Projects screens)
### Step 21: Theme system (Prototype: Settings → Theme)
### Step 22: Landing page deployment (docs/ → rawenv.com)

---

## Validation Rule
After each step, run:
1. The specific acceptance test listed above
2. `zig build test` (all tests still pass)
3. `zig build -Dtarget=x86_64-linux` (cross-compile check)
4. The prototype screen side-by-side with the real output — must match
