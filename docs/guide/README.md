# rawenv User Guide

Everything you need to use rawenv without reading the source.

| Guide | What it covers |
|-------|----------------|
| [Quickstart](quickstart.md) | Install → init → up → verify in under five minutes. |
| [Configuration reference](configuration.md) | Every `rawenv.toml` section and key, available packages, and on-disk layout. |
| [Service guides](services.md) | Per-service setup for Node, PostgreSQL, Redis, Meilisearch, Python, and PHP. |
| [Migration guide](migration.md) | Moving from docker-compose, MAMP/XAMPP, or Laravel Valet. |
| [Troubleshooting](troubleshooting.md) | Fixes for common issues. |

## The 30-second version

```bash
curl -fsSL rawenv.sh/install | sh   # install
cd my-project
rawenv init                         # detect stack → rawenv.toml
rawenv add node@22                  # download + verify a runtime
rawenv up                           # activate runtimes / start services
rawenv shell                        # enter a shell with the project's PATH + env
```

Native dev environments. Zero dependencies. One binary.
