# rawenv — Competitive Analysis & "How We Win" Roadmap

**Positioning:** rawenv is a single native binary (Zig) that detects a project's stack, downloads verified runtimes/services, and manages them with **OS-level isolation (Seatbelt / namespaces / Job Objects) — no Docker daemon, no VM**. Think "modern Laragon/MAMP for every stack, with the reproducibility of DDEV but without containers, and the speed/footprint of native."

This doc is a living reference. The exploratory + E2E runs (see `docs/qa-findings.md`) feed real gaps back here, and each gap becomes a PRD story.

---

## 1. The landscape (two overlapping markets we must beat)

### A. Container / VM-based dev runtimes
| Tool | How it works | Core features | Pros | Cons |
|------|--------------|---------------|------|------|
| **Docker Desktop + docker-compose** | Linux VM (HyperKit/WSL2) running the Docker daemon; `compose.yml` declares services | Images, compose orchestration, volumes, networks, healthchecks, `depends_on`, huge registry | Ubiquitous, reproducible, massive ecosystem | Heavy RAM/CPU, slow FS on macOS, licensing for big orgs, VM overhead, cold starts |
| **Podman / Podman Desktop** | Daemonless containers; rootless; `podman-compose`/Quadlet | Docker-compatible CLI, rootless, pods, systemd integration | No daemon, rootless security, OCI standard | Still needs a Linux VM on macOS, compose parity gaps, smaller ecosystem |
| **Colima** | Lima VM + containerd/Docker; CLI-only | `colima start`, Docker/k8s runtimes, configurable CPU/mem | Lightweight, scriptable, free | Still a VM, no GUI, manual tuning, FS perf |
| **OrbStack** | Bespoke fast Linux VM + container/k8s engine; native macOS app | Blazing container + Linux-machine UX, fast FS, low RAM, nice GUI, domains | Best-in-class speed/UX on macOS, tiny footprint | macOS-only, proprietary/paid, still containers/VM under the hood |
| **Rancher Desktop** | Lima/WSL VM + k3s + containerd/moby | k8s built in, Docker CLI, image build | Free, k8s focus | Heavy, VM-based, k8s complexity |
| **Lima / nerdctl** | Linux VMs on macOS | Generic Linux VMs, containerd | Flexible, free | Low-level, DIY |
| **Vagrant** | Full VMs (VirtualBox/etc.) | Boxes, provisioners | Full OS fidelity | Very heavy, slow, dated |

### B. Local "stack" managers (LAMP / per-language native)
| Tool | How it works | Core features | Pros | Cons |
|------|--------------|---------------|------|------|
| **Laragon** (Windows) | Native Apache/Nginx + PHP + MySQL bundle, auto-vhosts | Auto `.test` domains, quick-add versions, pretty URLs, one-click | Fast, no containers, great DX on Windows | Windows-only, PHP-centric, manual for non-PHP |
| **WAMP / MAMP / XAMPP** | Bundled native Apache/MySQL/PHP | One installer, GUI start/stop | Simple, classic | Single global stack, version conflicts, PHP/MySQL only, dated UX |
| **MAMP Pro** | Native stack + per-host config | Multi-host, SSL, version switch | Polished for PHP | Paid, PHP-centric, macOS/Windows only |
| **Laravel Herd** | Native PHP + Nginx + dnsmasq (macOS/Windows) | Instant PHP, `.test`, multiple PHP versions, MySQL/Redis add-ons (Pro) | Extremely fast, zero-config for Laravel | PHP/Laravel-focused, paid Pro tiers |
| **Laravel Valet** | Native PHP + dnsmasq + Nginx | `.test` domains, park/link sites | Minimal, fast | macOS, PHP-only, CLI-only |
| **ServBay** | Native bundled stack (PHP/Node/Python/Go + DB/cache) on macOS/Windows | Multi-version runtimes, `.test`-style local domains, GUI, no containers | Closest native multi-stack rival, polished GUI, no Docker | Proprietary/paid tiers, fixed runtime catalog, no committable per-project config, no deploy/IaC |
| **Laravel Sail** | Thin CLI wrapper over docker-compose | Pre-baked Laravel service stack, `sail up` | Trivial for Laravel teams already on Docker | Docker required, Laravel-shaped, all container overhead |

### C. Reproducible env managers (rawenv's closest cousins)
| Tool | How it works | Core features | Pros | Cons |
|------|--------------|---------------|------|------|
| **DDEV** | Docker-based, project-aware config (`.ddev/`) | Per-project services, routing, `.ddev.site`, add-ons, import DB | Great project DX, reproducible | Requires Docker, container overhead |
| **Lando** | Docker + recipes (`.lando.yml`) | Framework recipes, tooling, proxy | Powerful recipes | Docker, slower, complex config |
| **Devbox (Jetify)** | Nix under the hood, per-project shells | Reproducible packages, no Docker | Reproducible, fast shells | Nix learning curve, services limited |
| **Nix / devenv / flox** | Nix store + flakes | Fully reproducible, services (devenv) | Gold-standard reproducibility | Steep learning curve, ergonomics |
| **mise / asdf / proto** | Runtime version managers via shims | Per-project tool versions, plugins | Lightweight, great for runtimes | No services/DBs, no isolation, no orchestration |
| **Devcontainers** | Docker + VS Code spec | Editor-integrated containers | Standardized, portable | Docker, editor-coupled |
| **Tilt / Skaffold** | k8s dev loops | Live reload to clusters | Great for k8s teams | k8s-only, heavy |

### D. Domain / proxy helpers (single-feature rivals to our DNS + proxy)
| Tool | How it works | Core features | Pros | Cons |
|------|--------------|---------------|------|------|
| **dnsmasq + nginx (DIY)** | Hand-wired local resolver + vhosts | Total control | Free, flexible | Manual, fragile, per-machine drift |
| **Localias / Hotel / Caddy** | Local proxy mapping ports → friendly hostnames + TLS | `*.local`/`.test` routing, auto-HTTPS | Lightweight, focused | Single-purpose; you still assemble the rest of the stack yourself |

---

## 2. What every winner has in common (table stakes we must match)
1. **One-command up/down** for the whole project (`compose up`/`herd`/`ddev start`).
2. **Real service install that just works** (DB, cache, search) — now landed: resolver ships real download URLs + SHA256 verification (`compute-on-download` fallback) for node/postgres/redis/python/php/meilisearch. Remaining work is breadth of the catalog, not the mechanism.
3. **Service dependency ordering + health/readiness gates** (`depends_on` + healthcheck).
4. **Per-project isolated data dirs** and clean teardown (no cross-project bleed).
5. **`.test` domains + automatic TLS** and a reverse proxy (Valet/Herd/DDEV-class).
6. **Automatic port management** (no conflicts) — we have this.
7. **Logs + status + resource metrics** in a fast native GUI (OrbStack-class UX).
8. **Import from `docker-compose.yml`** (migration path = adoption).
9. **Reproducible, committable project config** (`rawenv.toml`) for teams.
10. **Cross-platform** (macOS/Linux/Windows) parity.

## 3. rawenv's structural advantages (why we can win)
- **No Docker daemon, no VM** → seconds-faster startup, far lower RAM, native FS speed (beats Docker/Colima/Podman/Rancher; matches OrbStack's footprint without a VM at all).
- **Single static Zig binary** → trivial install, cross-compiles to all three OSes.
- **OS-native isolation cells** (Seatbelt / namespaces+Landlock / Job Objects) → security without containers.
- **Stack-agnostic** (not PHP-only like Laragon/MAMP/Herd; not container-only like DDEV/Lando).
- **Built-in DNS, reverse proxy, tunnels, deploy (IaC) generation, AI assistant** in one tool.

## 4. Gaps to close to beat the competition (improvement backlog)

Status legend: ✅ done · 🟡 partial · ⬜ not started. Statuses reflect the code in
`src/` as of the last update and are re-checked whenever this doc is touched.

**P0 — table stakes (blockers):**
- ✅ **Real service install into the store** (prebuilt binaries + verified checksums). `src/core/resolver.zig` resolves node/postgres/redis/python/php/meilisearch to real URLs with SHA256 (or `compute-on-download`); `src/core/store.zig` downloads, verifies, and extracts. *Path to winning:* widen the catalog to match the recipe matrix in `shared/recipes/` so any detected service installs unattended.
- 🟡 **`rawenv up` starts services with health/readiness checks.** `runUp` → `service.up()` exists; readiness probing is implemented (`tcpProbe`, `httpProbe`, `HealthResult`). *Gaps:* no symmetrical `rawenv down` (teardown today goes through `destroy`), and explicit `depends_on` topological ordering is not yet enforced. *Path to winning:* add `down`, order startup by declared dependencies, and gate each start on the predecessor's readiness.
- 🟡 **docker-compose.yml → rawenv.toml migration on-ramp.** `src/core/detector.zig` already parses `docker-compose.yml` during `rawenv init` (`parseDockerComposeServices`). *Gap:* no dedicated `rawenv import` that maps images/ports/env/volumes faithfully. *Path to winning:* promote detection into a first-class importer so a `compose` user is one command from a working native stack.
- 🟡 **Per-instance isolated data dirs + clean `destroy`.** `ServiceInfo.data_dir` gives each service its own dir; `runDestroy` provides teardown. *Gap:* E2E proof of no cross-project bleed + idempotent destroy. *Path to winning:* lock this in with the integration suite under `tests/integration/`.

**P1 — parity:**
- 🟡 **`.test` domains + auto-TLS + reverse proxy wired to live services.** `src/network/dns.zig` and `src/network/proxy.zig` generate `/etc/hosts` and Caddyfile config. *Gap:* not yet bound to the live service registry / no automatic cert issuance. *Path to winning:* drive proxy + DNS straight from running `service.listServices()` output (Herd/DDEV-class, zero hand-editing).
- ⬜ **Native GUI: live logs, status, CPU/RAM per service, start/stop, one-click setup** (OrbStack-class). GUI scaffolding exists in `src/gui/` and `gui/`; real data wiring is pending.
- 🟡 **Service recipes for the full matrix** (DB/cache/search/queue/CMS/etc.). Rich recipe JSON lives in `shared/recipes/`; resolver only installs a subset today. *Path to winning:* close the recipe→resolver gap so every recipe is installable.
- ⬜ **DB snapshot/restore + seed import** (DDEV `import-db` equivalent).
- 🟡 **Cross-platform parity** (Linux/Windows execution, not just macOS). Platform shims exist (`src/platform/*`, `src/cells/*`) but probes/process stats no-op on Windows. *Path to winning:* implement Windows/Linux readiness + status to match macOS.

**P2 — differentiation (how we pull ahead):**
- ⬜ **Instant cold-start benchmark vs Docker/Colima/OrbStack** (publish numbers). *Path to winning:* a reproducible benchmark in CI turns our "no VM" claim into a headline metric.
- 🟡 **AI-driven setup: detect → propose optimal stack → apply**, with autonomy levels. `src/ai/` (cascade, context, proactive) is scaffolded. *Path to winning:* wire AI suggestions to the real detector + resolver so setup is conversational.
- 🟡 **One-command deploy from the same config** (Terraform/Ansible/OCI) — scaffolded in `src/deploy/`. *Path to winning:* a single `rawenv.toml` that runs locally *and* deploys is something no competitor offers.
- 🟡 **Tunnels/sharing built in** (no ngrok account juggling). `src/network/tunnel.zig` generates SSH tunnel commands. *Path to winning:* one-command public URL with no third-party signup.
- ⬜ **Team mode: committable `rawenv.toml` + lockfile** for reproducible runtimes (Nix-class reproducibility without Nix).
- ⬜ **Resource governance per cell** (CPU/mem caps) surfaced in GUI, backed by the isolation cells.

## 5. Cross-reference: QA findings → backlog

This section ties the backlog above to live QA/E2E results in
[`docs/qa-findings.md`](./qa-findings.md). The process rule there: every **blocker**
and **major** finding becomes a user story before `VERIFY-040`, and the gap it
exposes is reflected as an unchecked/partial item above.

| QA finding | Severity | Area | Maps to backlog item |
|------------|----------|------|----------------------|
| _none logged yet_ | — | — | — |

**Current state:** `qa-findings.md` reports **0 findings** (log initialized under
QA-050, no E2E/exploratory runs have produced bugs yet). There are therefore no
QA-sourced gaps to fold in beyond the architectural gaps already tracked in
section 4. When the first finding lands:
1. Record it in `qa-findings.md` with an ID (`QF-NNN`) and severity.
2. Add a row to the table above linking the finding to the backlog item it
   affects (or add a new P0/P1/P2 item if it exposes a fresh gap).
3. For blockers/majors, file the user story and update the item's status marker.

## 6. Win condition (the one-liner)
> "Everything docker-compose/DDEV give you for a project — services, domains, isolation, reproducibility — but **native, instant, and tiny**, for **any** stack, on all three OSes, with a GUI as nice as OrbStack and zero containers."

*Maintained from exploratory + E2E findings (`docs/qa-findings.md`). Each unchecked box should become a `prd.json` user story.*
