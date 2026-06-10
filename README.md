# rawenv

**Native dev environments. Zero dependencies. One binary.**

[![CI](https://github.com/juslintek/rawenv/actions/workflows/ci.yml/badge.svg)](https://github.com/juslintek/rawenv/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/juslintek/rawenv?sort=semver)](https://github.com/juslintek/rawenv/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

rawenv detects your project stack, downloads verified runtimes, and manages everything through OS-level isolation — no Docker, no VMs, no overhead.

Built with Zig 0.16. Cross-compiles to macOS, Linux, and Windows.

## Install

Download the latest release binary for your platform into `~/.rawenv/bin`.

**macOS** (auto-detects Apple Silicon vs Intel):

```bash
mkdir -p "$HOME/.rawenv/bin"
case "$(uname -m)" in arm64|aarch64) A=aarch64 ;; *) A=x86_64 ;; esac
curl -fsSL "https://github.com/juslintek/rawenv/releases/latest/download/rawenv-${A}-macos.tar.gz" \
  | tar -xz -C "$HOME/.rawenv/bin"
```

**Linux** (auto-detects arm64 vs x86_64):

```bash
mkdir -p "$HOME/.rawenv/bin"
case "$(uname -m)" in arm64|aarch64) A=aarch64 ;; *) A=x86_64 ;; esac
curl -fsSL "https://github.com/juslintek/rawenv/releases/latest/download/rawenv-${A}-linux.tar.gz" \
  | tar -xz -C "$HOME/.rawenv/bin"
```

For **Windows**, download `rawenv-x86_64-windows.zip` from the
[releases page](https://github.com/juslintek/rawenv/releases/latest) and extract `rawenv.exe`.
macOS users who prefer a packaged app can grab `rawenv-macos.dmg` from the same page.

Add the binary to your `PATH` (add this line to `~/.zshrc` or `~/.bashrc` to make it permanent):

```bash
export PATH="$HOME/.rawenv/bin:$PATH"
```

Verify the install:

```console
$ rawenv --version
0.2.0
```

## Quick Start

Run `rawenv init` inside any project. It scans your manifests (`package.json`,
`composer.json`, `.env`, `docker-compose.yml`), detects runtimes and services,
and writes a `rawenv.toml`:

```console
$ rawenv init
Created rawenv.toml
Detected runtimes:
  node 22
Detected services:
  postgresql 16
```

Check project health at any time with `rawenv status`:

```console
$ rawenv status
Project: my-app
Config:  rawenv.toml (valid)

Runtimes:
  node          22         installed

Services:
  NAME            VERSION    PORT   STATUS
  postgresql    16.9.0     5432   stopped

Warnings:
  ⚠ postgresql: binary not installed — run `rawenv add postgresql@16.9.0`
```

List configured runtimes and services with `rawenv services ls`:

```console
$ rawenv services ls
NAME            VERSION    STATUS
──────────────  ─────────  ──────────────
node            22         installed
postgresql      16         stopped
```

Then install what's missing, activate, and drop into an isolated shell:

```bash
rawenv add postgresql@16   # download, verify SHA256, extract to the store
rawenv up                  # activate runtimes via symlinks
rawenv shell               # enter a shell with modified PATH + env vars
```

## Command Reference

| Command | Description |
|---------|-------------|
| `rawenv init` | Detect project and generate `rawenv.toml` |
| `rawenv import <file>` | Import a `docker-compose.yml` into `rawenv.toml` |
| `rawenv detect` | Detect runtimes/services (`--json`); writes no files |
| `rawenv add <pkg>@<ver>` | Install a package (e.g. `rawenv add node@22`) |
| `rawenv up` | Activate all configured runtimes |
| `rawenv down` | Stop all services (reverse dependency order) |
| `rawenv services ls` | List configured runtimes/services with status |
| `rawenv status` | Quick project health check (`--json`) |
| `rawenv shell` | Enter rawenv shell with modified PATH |
| `rawenv dns` | Generate `/etc/hosts` entries for the project |
| `rawenv proxy` | Generate Caddy reverse proxy config |
| `rawenv tunnel <port>` | Print a tunnel command (cloudflared/bore/ngrok) |
| `rawenv connections` | Show service dependency map |
| `rawenv cell info` | Show available isolation backends |
| `rawenv discover` | Scan for projects on this machine |
| `rawenv destroy` | Remove this project's isolated data dirs (`--force` to skip prompt) |
| `rawenv uninstall` | Remove rawenv from this machine |
| `rawenv tui` | Launch the TUI dashboard |
| `rawenv gui` | Launch the GUI window (requires a raylib build — see below) |
| `rawenv menubar` | Launch the macOS menu bar status item |
| `rawenv ai "question"` | Ask the AI assistant (one-shot) |
| `rawenv deploy generate` | Generate IaC files (Terraform, Ansible, Containerfile) |
| `rawenv deploy apply` | Run deployment (dry-run by default) |

Run `rawenv --help` for the full list, or `rawenv <command> --json` where supported.

## How It Works

rawenv stores runtimes in `~/.rawenv/store/{name}-{version}/` and activates them by creating symlinks in `~/.rawenv/bin/`. No global installs, no version conflicts.

```
~/.rawenv/
├── bin/              # symlinks to active runtimes (add to PATH)
└── store/
    ├── node-22/      # extracted runtime
    ├── postgresql-16/
    └── redis-7/
```

Project configuration lives in `rawenv.toml`:

```toml
[project]
name = "my-app"

[runtimes]
node = "22"

[services]
postgresql = "16"
redis = "7"

[detect]
auto = true
```

## Architecture

```
rawenv (single binary, written in Zig)
├── core/       config, detector, resolver, store, service manager, shell
├── network/    DNS, reverse proxy, tunnel, connection map
├── cells/      OS-native isolation (Linux namespaces, macOS Seatbelt, Windows Job Objects)
├── deploy/     Terraform, Ansible, OCI container images
├── ai/         LLM provider cascade, context builder, chat
├── tui/        Terminal dashboard
└── gui/        Native desktop app (raylib, opt-in)
```

Isolation backends by platform:

| Platform | Backends |
|----------|----------|
| Linux | cgroups v2, namespaces, Landlock |
| macOS | Seatbelt (sandbox-exec) |
| Windows | Job Objects |

`rawenv cell info` reports the backends available on the current machine:

```console
$ rawenv cell info
Isolation backends available on this OS:
  seatbelt (sandbox-exec) — macOS App Sandbox
```

## Build from Source

Requires [Zig 0.16.0+](https://ziglang.org/download/):

```bash
git clone https://github.com/juslintek/rawenv
cd rawenv
zig build
./zig-out/bin/rawenv --help
```

The GUI window links raylib, which is compiled from source and is opt-in:

```bash
zig build -Dgui=true
./zig-out/bin/rawenv gui
```

Cross-compile:

```bash
zig build -Dtarget=x86_64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=aarch64-macos
```

Run tests:

```bash
zig build test
```

## License

MIT — see [LICENSE](LICENSE).
