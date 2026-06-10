# Troubleshooting

Common issues and how to fix them. If something here doesn't match what you're
seeing, run `rawenv status` for a quick health check and
`rawenv ai "..."` to ask the built-in assistant.

---

## `rawenv: command not found`

The binary isn't on your `PATH`. The installer adds it to your shell rc files,
but the current shell hasn't reloaded.

```bash
export PATH="$HOME/.rawenv/bin:$PATH"
```

To make it permanent, ensure this line is in `~/.zshrc`, `~/.bashrc`, or
`~/.profile`, then restart your terminal. Verify:

```bash
rawenv --version
which rawenv          # ~/.rawenv/bin/rawenv
```

---

## `rawenv.toml already exists — skipping`

`rawenv init` won't overwrite an existing config. This is intentional. To
regenerate from scratch, remove the file first:

```bash
rm rawenv.toml
rawenv init
```

To see what *would* be detected without writing anything:

```bash
rawenv detect
```

---

## `rawenv.toml not found in the current directory`

You're not in a project root, or `init` was never run. Confirm your location
and initialize:

```bash
pwd
rawenv init
```

---

## `Unknown package` when running `rawenv add`

The package name isn't one rawenv knows. Valid names:

```
node, postgres (postgresql), redis, python, php, meilisearch
```

Check spelling and use the `name@version` form:

```bash
rawenv add postgres@16     # correct
rawenv add postgresql@16   # also correct (alias)
```

---

## `Unknown version` when running `rawenv add`

The version isn't pinned in rawenv yet. Supported versions:

| Package      | Versions         |
|--------------|------------------|
| node         | `22`             |
| postgres     | `16`, `17`, `18` |
| redis        | `7`              |
| python       | `3.12`           |
| php          | `8.4`            |
| meilisearch  | `1.12`           |

Use a supported version:

```bash
rawenv add node@22
```

---

## SHA256 / checksum verification failed

rawenv verifies the SHA256 of every download before extracting. A failure means
the download was corrupted or incomplete (often a flaky network or a proxy
mangling the response).

1. Retry the command — most failures are transient:
   ```bash
   rawenv add node@22
   ```
2. If you're behind a corporate proxy or VPN, confirm it isn't rewriting binary
   downloads, then retry.
3. Clear a partial download and try again:
   ```bash
   rm -rf ~/.rawenv/store/<name>-<version>
   rawenv add <name>@<version>
   ```

---

## A runtime isn't found after `rawenv up`

`rawenv up` symlinks runtimes into `~/.rawenv/bin/`, but that directory must be
on your `PATH`, and you should be in a shell that picked it up.

```bash
rawenv up
rawenv shell           # opens a shell with the correct PATH
node --version
```

If it still isn't found, confirm the symlink exists:

```bash
ls -l ~/.rawenv/bin/
```

A missing symlink usually means the package wasn't installed — run
`rawenv add <name>@<version>` first, then `rawenv up`.

---

## Port already in use

A service can't bind its port because something else is listening. Check what's
using it (Postgres defaults to 5432, Redis 6379, Meilisearch 7700):

```bash
lsof -i :5432
```

Either stop the conflicting process, or assign a different port in
`rawenv.toml`:

```toml
[services.postgres]
version = "16"
port = 5433
```

Then re-run `rawenv up`. Remember to update any connection string that hard-codes
the old port.

---

## A service never becomes ready (`rawenv up` times out)

`rawenv up` polls each service until it passes its health check or the timeout
elapses. If a service is slow to start, raise the timeout:

```toml
[services.postgres.health]
type = "tcp"
timeout = 60
```

If the health probe is wrong for the service, set the right strategy. Use `http`
for web services and `tcp` for raw datastores, or disable gating entirely:

```toml
[services.meilisearch.health]
type = "http"
path = "/health"

[services.some-service.health]
type = "none"      # skip readiness checks
```

Then check the per-service status:

```bash
rawenv services ls
```

---

## `.test` domains don't resolve

`rawenv dns` prints the `/etc/hosts` entries, but writing to `/etc/hosts`
requires elevated permissions. Make sure the entries were actually added:

```bash
rawenv dns
grep rawenv /etc/hosts
```

If they're missing, add them with the appropriate privileges, then flush your
DNS cache:

```bash
# macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

---

## Deploy generate fails

`rawenv deploy generate` needs a valid `rawenv.toml` in the current directory.

```
Error: rawenv.toml not found in the current directory. Run `rawenv init` first.
```

Run `rawenv init` (or `cd` into the project root) first. If you see a parse
error, check `rawenv.toml` for TOML syntax mistakes — unbalanced brackets or
unquoted string values are the usual culprits.

> `rawenv deploy generate` is not supported on Windows yet.

---

## Removing things

| Goal                                   | Command                          |
|----------------------------------------|----------------------------------|
| Stop all services                      | `rawenv down`                    |
| Delete this project's service data     | `rawenv destroy` (`--force` to skip prompt) |
| Remove rawenv from this machine        | `rawenv uninstall`               |

`rawenv destroy` only removes `~/.rawenv/data/<project>/` — your `rawenv.toml`
and installed runtimes in the store are left intact.

---

## Still stuck?

- `rawenv status --json` — machine-readable health output for bug reports.
- `rawenv ai "why won't postgres start?"` — ask the built-in assistant.
- File an issue at <https://github.com/juslintek/rawenv/issues>.
