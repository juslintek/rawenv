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

---

## 2. What every winner has in common (table stakes we must match)
1. **One-command up/down** for the whole project (`compose up`/`herd`/`ddev start`).
2. **Real service install that just works** (DB, cache, search) — our current #1 gap (resolver placeholders).
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
**P0 — table stakes (blockers):**
- [ ] Real service install into the store (prebuilt binaries + verified checksums) — *resolver placeholders today*.
- [ ] `rawenv up`/`down` that actually starts/stops all services in dependency order with **health/readiness checks**.
- [ ] **docker-compose.yml importer** → `rawenv.toml` (migration on-ramp).
- [ ] Per-instance isolated data dirs + clean `destroy` (verified by E2E).

**P1 — parity:**
- [ ] `.test` domains + auto-TLS + reverse proxy wired to live services (not just config gen).
- [ ] Native GUI: live logs, status, CPU/RAM per service, start/stop, one-click setup (OrbStack-class).
- [ ] Service recipes for the full matrix (DB/cache/search/queue/CMS/etc.) with dev-optimized configs.
- [ ] DB snapshot/restore + seed import (DDEV `import-db` equivalent).
- [ ] Cross-platform parity (Linux/Windows execution, not just macOS GUI).

**P2 — differentiation (how we pull ahead):**
- [ ] **Instant cold start** benchmark vs Docker/Colima/OrbStack (publish numbers).
- [ ] AI-driven setup: detect → propose optimal stack → apply, with autonomy levels.
- [ ] One-command **deploy** from the same config (Terraform/Ansible/OCI) — already scaffolded.
- [ ] Tunnels/sharing built in (no ngrok account juggling).
- [ ] Team mode: committable `rawenv.toml` + lockfile for reproducible runtimes (Nix-class reproducibility without Nix).
- [ ] Resource governance per cell (CPU/mem caps) surfaced in GUI.

## 5. Win condition (the one-liner)
> "Everything docker-compose/DDEV give you for a project — services, domains, isolation, reproducibility — but **native, instant, and tiny**, for **any** stack, on all three OSes, with a GUI as nice as OrbStack and zero containers."

*Maintained from exploratory + E2E findings (`docs/qa-findings.md`). Each unchecked box should become a `prd.json` user story.*
