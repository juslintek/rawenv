# Migration Guide

Moving an existing project to rawenv. This page covers the most common
starting points: Docker Compose, MAMP/XAMPP, and Laravel Valet.

The general path is the same regardless of where you're coming from:

1. Generate a `rawenv.toml` (`rawenv import` or `rawenv init`).
2. Install the runtimes (`rawenv add`).
3. Activate and verify (`rawenv up`, `rawenv shell`).
4. Point your app's config at the rawenv connection URLs.

---

## From Docker Compose

rawenv can translate a `docker-compose.yml` directly.

### Import

```bash
cd my-project
rawenv import docker-compose.yml
```

`import` parses the Compose file and writes an equivalent `rawenv.toml`:

- Recognized database/runtime images map to rawenv packages
  (`postgres:16` → `[services.postgres]` with `version = "16"`).
- Port mappings, `environment` variables, and `depends_on` edges are preserved.
- Anything rawenv can't represent natively (custom `Dockerfile` builds,
  networks, named volumes, unknown images) is reported as a **warning** rather
  than failing the import.

Review the warnings, then review the generated file.

### Example

A Compose file like this:

```yaml
services:
  db:
    image: postgres:16
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: myapp
  cache:
    image: redis:7
    depends_on:
      - db
```

imports to:

```toml
name = "my-project"
version = "1"

[services.postgres]
version = "16"
port = 5432

[services.postgres.env]
POSTGRES_DB = "myapp"

[services.redis]
version = "7"
depends_on = ["postgres"]
```

(The project name is taken from the current directory. The top-level
`name`/`version` form is equivalent to a `[project]` section.)

### Finish up

```bash
rawenv add postgres@16
rawenv add redis@7
rawenv up
rawenv shell
```

### What's different from Docker

- Services run as **native processes**, not containers — no daemon, no images,
  faster startup, lower memory.
- Data lives in `~/.rawenv/data/<project>/` instead of named volumes. Migrate
  existing data with a logical dump/restore (e.g. `pg_dump` from the container,
  `psql` into the rawenv instance).
- Custom-built images have no rawenv equivalent. Run that code directly with a
  rawenv runtime (Node, PHP, Python), or keep that one piece in Docker.

---

## From MAMP / XAMPP

MAMP and XAMPP bundle Apache, PHP, and MySQL. With rawenv you pick the exact
runtimes you need and skip the rest.

### Set up

```bash
cd my-php-project
rawenv init          # detects PHP from composer.json, if present
```

If detection misses something, edit `rawenv.toml`:

```toml
[project]
name = "my-php-project"

[runtimes]
php = "8.4"

[services.postgres]
version = "16"
```

```bash
rawenv add php@8.4
rawenv add postgres@16
rawenv up
```

### Run the app

Use PHP's built-in server inside the rawenv shell instead of MAMP's Apache:

```bash
rawenv shell
php -S localhost:8000 -t public
```

### Notes

- rawenv ships PostgreSQL rather than MySQL today. If your app requires MySQL,
  keep that one service elsewhere for now and use rawenv for PHP and the rest of
  the stack.
- Point your app's database config at `DATABASE_URL`
  (`postgresql://localhost:5432`), which rawenv exports in the shell.

---

## From Laravel Valet

Valet gives you `*.test` domains and a PHP runtime. rawenv covers both, plus the
databases your app needs.

### Set up

```bash
cd my-laravel-app
rawenv init
```

```toml
[project]
name = "my-laravel-app"

[runtimes]
php = "8.4"
node = "22"

[services.postgres]
version = "16"

[services.redis]
version = "7"
```

```bash
rawenv add php@8.4
rawenv add node@22
rawenv add postgres@16
rawenv add redis@7
rawenv up
```

### `.test` domains

Generate `/etc/hosts` entries for the project. rawenv maps `<project>.test` and
`<service>.<project>.test` to `127.0.0.1`:

```bash
rawenv dns
```

For HTTPS and clean routing, generate a Caddy reverse-proxy config:

```bash
rawenv proxy
```

### Serve

```bash
rawenv shell
php artisan serve
# or the built-in server:
php -S my-laravel-app.test:8000 -t public
```

Update `.env` to use the rawenv connection URLs:

```ini
DB_CONNECTION=pgsql
DATABASE_URL=postgresql://localhost:5432
REDIS_URL=redis://localhost:6379
```

---

## General tips

- **Keep `rawenv.toml` in version control.** It's the single source of truth
  for your team's environment — the equivalent of a `docker-compose.yml`.
- **Migrate data with logical dumps**, not by copying raw data directories
  between different database versions.
- **Run `rawenv status`** after migrating to confirm everything is healthy.
- **Mix and match.** rawenv doesn't have to own your whole stack. Move what it
  supports and leave the rest where it is.

See [Troubleshooting](troubleshooting.md) if something doesn't come up cleanly.
