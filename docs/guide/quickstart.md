# Quickstart

Get a project running with rawenv in under five minutes — no Docker, no VMs, no
global installs.

## 1. Install (30 seconds)

```bash
curl -fsSL rawenv.sh/install | sh
```

The installer downloads a single static binary to `~/.rawenv/bin/rawenv` and
adds that directory to your `PATH` in `~/.zshrc`, `~/.bashrc`, and
`~/.profile`. Restart your shell, or load the new `PATH` now:

```bash
export PATH="$HOME/.rawenv/bin:$PATH"
```

Verify the install:

```bash
rawenv --version
```

> **Windows / manual install:** download the matching binary
> (`rawenv-<os>-<arch>`) from the
> [GitHub releases page](https://github.com/juslintek/rawenv/releases) and put
> it on your `PATH`.

## 2. Initialize your project (10 seconds)

From the root of an existing project:

```bash
cd my-project
rawenv init
```

`init` scans the directory, detects the stack (for example a `package.json`
pins Node, a `composer.json` pins PHP), and writes a `rawenv.toml`. If a
`rawenv.toml` already exists, `init` leaves it untouched.

Example output:

```
Created rawenv.toml
Detected runtimes:
  node 22
Detected services:
  postgresql 16
```

Want to see what would be detected without writing a file?

```bash
rawenv detect          # human-readable
rawenv detect --json   # machine-readable
```

## 3. Install the runtimes (1–2 minutes)

Download and install each runtime your project needs. rawenv verifies the
SHA256 of every download before extracting it into the store:

```bash
rawenv add node@22
rawenv add postgres@16
rawenv add redis@7
```

Each runtime lands in `~/.rawenv/store/<name>-<version>/`. Installs are
content-addressed by version, so two projects on `node@22` share one copy.

## 4. Activate and verify (30 seconds)

Activate every runtime listed in `rawenv.toml` by symlinking it into
`~/.rawenv/bin/`:

```bash
rawenv up
```

Check the state of the project:

```bash
rawenv services ls    # list configured runtimes/services with status
rawenv status         # quick health check
```

Drop into a shell with the project's `PATH` and service environment variables
(`DATABASE_URL`, `REDIS_URL`, …) already exported:

```bash
rawenv shell
node --version        # resolves to the rawenv-managed Node
echo "$DATABASE_URL"  # postgresql://localhost:5432
```

When you're done, stop the running services (in reverse dependency order):

```bash
rawenv down
```

## You're set

In five commands you went from a bare checkout to a fully provisioned,
isolated environment:

```bash
rawenv init
rawenv add node@22
rawenv add postgres@16
rawenv up
rawenv shell
```

## Next steps

- [Configuration reference](configuration.md) — every `rawenv.toml` key explained.
- [Service guides](services.md) — per-service setup for Node, PostgreSQL, Redis, Meilisearch.
- [Migrating an existing project](migration.md) — from docker-compose, MAMP, or Valet.
- [Troubleshooting](troubleshooting.md) — fixes for common issues.
