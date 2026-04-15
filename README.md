# ⚡ rawenv

**Raw native dev environments. Zero overhead.**

rawenv auto-detects your project stack, installs runtimes and services natively (no Docker, no VMs), and manages everything with OS-level isolation.

## Install

```bash
curl -fsSL rawenv.sh/install | sh
```

## Quick Start

```bash
cd my-project
rawenv init          # scans project, generates rawenv.toml
rawenv up            # installs & starts all services natively
rawenv tui           # interactive terminal dashboard
rawenv shell         # enter isolated environment
```

## Features

- **Auto-detect** — scans package.json, composer.json, .env, docker-compose.yml
- **Native install** — no containers, no VMs, bare metal performance
- **Isolation Cells** — OS-native sandboxing (Linux namespaces, macOS Seatbelt, Windows AppContainer)
- **AI Assistant** — built-in help via free LLMs (Groq, Cerebras, Cloudflare)
- **Deploy** — generate Terraform/Ansible, deploy to any cloud provider
- **Tunneling** — expose local services to public URLs
- **DNS masking** — `.test` domains for local services
- **TUI + GUI** — terminal dashboard and native desktop app

## Architecture

```
rawenv (single ~10MB binary, written in Zig)
├── Core      — config, detector, resolver, store, service manager
├── Network   — DNS, proxy, tunnel, connection manager
├── Cells     — OS-native process isolation
├── Deploy    — Terraform, Ansible, OCI images
├── AI        — LLM cascade, proactive suggestions
├── TUI       — terminal dashboard (ZigZag)
└── GUI       — native desktop (raylib+ImGui / AppKit / Win32)
```

## Build from Source

Requires [Zig 0.15+](https://ziglang.org/download/):

```bash
git clone https://github.com/juslintek/rawenv
cd rawenv
zig build
./zig-out/bin/rawenv --help
```

## License

MIT
