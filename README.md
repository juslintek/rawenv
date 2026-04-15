# rawenv

**Native dev environments. Zero dependencies. One binary.**

rawenv detects your project stack, downloads verified runtimes, and manages everything through OS-level isolation — no Docker, no VMs, no overhead.

Built with Zig 0.15. Cross-compiles to macOS, Linux, and Windows.

## Install

```bash
curl -fsSL rawenv.sh/install | sh
```

## Quick Start

```bash
cd my-project
rawenv init          # detect project, generate rawenv.toml
rawenv add node@22   # download, verify SHA256, extract to store
rawenv up            # activate runtimes via symlinks
rawenv shell         # enter shell with modified PATH + env vars
```

## Command Reference

| Command | Description |
|---------|-------------|
| `rawenv init` | Detect project stack and generate `rawenv.toml` |
| `rawenv add <pkg>@<ver>` | Download, verify SHA256, and extract a runtime to the store |
| `rawenv up` | Activate all configured runtimes via symlinks in `~/.rawenv/bin/` |
| `rawenv services ls` | Show configured runtimes/services with status |
| `rawenv shell` | Enter a shell with modified PATH and environment variables |
| `rawenv dns` | Generate `/etc/hosts` entries for project services |
| `rawenv proxy` | Generate Caddyfile reverse proxy configuration |
| `rawenv tunnel <port>` | Generate SSH tunnel command for a local port |
| `rawenv connections` | Show service dependency map from `rawenv.toml` |
| `rawenv cell info` | Show available OS isolation backends for this platform |
| `rawenv discover` | Scan the machine for projects and their stacks |
| `rawenv tui` | Launch terminal dashboard with live data |
| `rawenv gui` | Launch native GUI window (stub — requires raylib) |
| `rawenv ai "question"` | Ask the AI assistant with provider cascade |
| `rawenv deploy generate` | Generate Terraform, Ansible, and Containerfile from config |
| `rawenv deploy apply` | Run deployment (dry-run by default) |

## How It Works

rawenv stores runtimes in `~/.rawenv/store/{name}-{version}/` and activates them by creating symlinks in `~/.rawenv/bin/`. No global installs, no version conflicts.

```
~/.rawenv/
├── bin/              # symlinks to active runtimes (add to PATH)
└── store/
    ├── node-22/      # extracted runtime
    ├── postgres-16/
    └── redis-7/
```

Project configuration lives in `rawenv.toml`:

```toml
name = "my-app"
version = "1"

[services.node]
version = "22"

[services.postgres]
version = "16"

[services.redis]
version = "7"
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
└── gui/        Native desktop app (stub)
```

Isolation backends by platform:

| Platform | Backends |
|----------|----------|
| Linux | cgroups v2, namespaces, Landlock |
| macOS | Seatbelt (sandbox-exec) |
| Windows | Job Objects |

## Build from Source

Requires [Zig 0.15.2+](https://ziglang.org/download/):

```bash
git clone https://github.com/juslintek/rawenv
cd rawenv
zig build
./zig-out/bin/rawenv --help
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
