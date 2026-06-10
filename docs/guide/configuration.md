# Configuration Reference

Every rawenv project is described by a single `rawenv.toml` file at the project
root. This page documents every section and key.

`rawenv init` generates this file for you; you rarely need to write it by hand.
But because it's plain TOML, editing it is straightforward.

## Minimal example

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

## Full example

```toml
[project]
name = "my-app"

# Language runtimes added to PATH by `rawenv up`.
[runtimes]
node = "22"
php = "8.4"

# Background services started by `rawenv up`.
[services.postgres]
version = "16"
port = 5433              # override the default 5432
depends_on = []

[services.postgres.env]
POSTGRES_DB = "myapp"
POSTGRES_USER = "myapp"

[services.postgres.health]
type = "tcp"             # auto | tcp | http | none
timeout = 30             # seconds to wait for readiness
port = 5433              # 0 = use the service's resolved port

[services.redis]
version = "7"
depends_on = ["postgres"]

[services.meilisearch]
version = "1.12"

[services.meilisearch.health]
type = "http"
path = "/health"
timeout = 20

[detect]
auto = true
```

---

## `[project]`

| Key    | Type   | Required | Description                              |
|--------|--------|----------|------------------------------------------|
| `name` | string | yes      | Project name. Used for DNS domains (`<name>.test`), the per-project data directory, and the shell prompt context. |

```toml
[project]
name = "my-app"
```

> A top-level `name = "my-app"` (without the `[project]` header) is also
> accepted for compatibility, along with an optional `version` key that is
> currently ignored.

---

## `[runtimes]`

Language runtimes that `rawenv up` activates by symlinking into
`~/.rawenv/bin/`. Each key is a package name and each value is a version.

```toml
[runtimes]
node = "22"
python = "3.12"
php = "8.4"
```

Equivalent expanded form (useful when you want per-runtime sub-keys later):

```toml
[runtimes.node]
version = "22"
```

See [Available packages](#available-packages) for valid names and versions.

---

## `[services]`

Background services (databases, caches, search engines) that `rawenv up`
starts and `rawenv down` stops. There are two equivalent syntaxes.

**Inline form** — one line per service, value is the version:

```toml
[services]
postgresql = "16"
redis = "7"
```

**Table form** — required when you need a port, dependencies, env vars, or a
health policy:

```toml
[services.postgres]
version = "16"
port = 5433
depends_on = ["redis"]
```

### Per-service keys (`[services.<name>]`)

| Key          | Type            | Default  | Description |
|--------------|-----------------|----------|-------------|
| `version`    | string          | `latest` | Package version to run. |
| `port`       | integer         | `0`      | TCP port. `0` means use the service's default (Postgres 5432, Redis 6379, Meilisearch 7700). |
| `depends_on` | array of string | `[]`     | Services to start before this one (and stop after it). Match by full key or base type. |

```toml
[services.postgres]
version = "16"
port = 5433
depends_on = ["redis"]
```

### Multiple instances of one service

Use a dotted key — `[services.<type>.<instance>]`. The part before the first
dot is the base service type:

```toml
[services.postgres.primary]
version = "16"
port = 5432

[services.postgres.replica]
version = "16"
port = 5433
```

Each instance gets its own data directory under
`~/.rawenv/data/<project>/<instance>/`.

### `[services.<name>.health]`

Readiness policy. After starting a service, `rawenv up` polls it until it
becomes ready or the timeout elapses.

| Key       | Type    | Default | Description |
|-----------|---------|---------|-------------|
| `type`    | enum    | `auto`  | Probe strategy: `auto`, `tcp`, `http`, or `none`. `auto` uses TCP for datastores and HTTP for web services. `none` disables readiness gating. |
| `timeout` | integer | `30`    | Maximum seconds to wait for readiness. |
| `path`    | string  | `/`     | Request path for HTTP probes (ignored for TCP). |
| `port`    | integer | `0`     | Port to probe. `0` means use the service's resolved port. |

> `kind` is accepted as an alias for `type`.

```toml
[services.meilisearch.health]
type = "http"
path = "/health"
timeout = 20
```

### `[services.<name>.env]`

Environment variables passed to the service process. Each key/value pair is one
variable.

```toml
[services.postgres.env]
POSTGRES_DB = "myapp"
POSTGRES_USER = "myapp"
POSTGRES_PASSWORD = "secret"
```

---

## `[detect]`

| Key    | Type    | Default | Description |
|--------|---------|---------|-------------|
| `auto` | boolean | `false` | When `true`, rawenv may auto-detect stack changes on subsequent runs. `rawenv init` sets this to `true`. |

```toml
[detect]
auto = true
```

---

## Available packages

These are the package names and versions rawenv knows how to download and
verify. Short versions (e.g. `16`) resolve to a pinned full version (e.g.
`16.9.0`).

| Package                  | Versions            | Default port |
|--------------------------|---------------------|--------------|
| `node`                   | `22`                | 3000 (app)   |
| `postgres` / `postgresql`| `16`, `17`, `18`    | 5432         |
| `redis`                  | `7`                 | 6379         |
| `python`                 | `3.12`              | —            |
| `php`                    | `8.4`               | —            |
| `meilisearch`            | `1.12`              | 7700         |

> `postgres` and `postgresql` are interchangeable names for the same package.

Install a package with `rawenv add <name>@<version>`:

```bash
rawenv add node@22
rawenv add postgres@16
```

---

## Environment variables set by `rawenv shell`

When you run `rawenv shell` (or `rawenv up` activates a service), rawenv exports
connection variables for recognized services:

| Variable          | Value                            | Set when…                  |
|-------------------|----------------------------------|----------------------------|
| `RAWENV_ACTIVE`   | `1`                              | always                     |
| `RAWENV_PROJECT`  | the project name                 | always                     |
| `DATABASE_URL`    | `postgresql://localhost:5432`    | Postgres is configured     |
| `REDIS_URL`       | `redis://localhost:6379`         | Redis is configured        |
| `MEILISEARCH_URL` | `http://localhost:7700`          | Meilisearch is configured  |

---

## On-disk layout

```
~/.rawenv/
├── bin/                       # symlinks to active runtimes (added to PATH)
├── store/
│   ├── node-22.15.0/          # extracted, content-addressed runtimes
│   └── postgres-16.9.0/
└── data/
    └── <project-key>/         # per-project service data
        └── postgres/          # one dir per service instance
```

Runtimes are shared across projects; service data is isolated per project.
`rawenv destroy` removes this project's `data/` directory (add `--force` to skip
the confirmation prompt).
