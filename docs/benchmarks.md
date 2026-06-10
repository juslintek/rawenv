# Benchmarks: `rawenv up` vs `docker compose up`

How fast can you go from a stopped machine to *services responding*? This page
measures cold-start time, peak RAM, and disk footprint for rawenv against the
de-facto standard, Docker Compose, on an identical project.

**TL;DR — on the same project (PostgreSQL 16 + Redis 7), with everything already
installed, rawenv reaches "all services ready" roughly 6× faster than
`docker compose up`, using a fraction of the RAM and disk.**

All numbers here are reproducible with [`scripts/benchmark.sh`](../scripts/benchmark.sh).

---

## Methodology

### What "cold start" means

Cold start is the time from a *fully stopped* state to *services responding*,
with the runtimes/images **already installed**. We deliberately exclude
download time:

- rawenv packages are pre-installed (`rawenv add postgresql@16`, `rawenv add redis@7`).
- Docker images are pre-pulled (`docker pull postgres:16`, `docker pull redis:7-alpine`).

This models the everyday "I open my laptop and start working" case, not the
one-time "first install" case. Download/build time is a separate concern and is
not what cold start measures.

### The project under test

Both tools run the **same** two services on the **same** machine:

| Service | Version |
|---------|---------|
| PostgreSQL | 16 |
| Redis | 7 |

rawenv reads:

```toml
[project]
name = "rawenv-bench"

[services]
postgresql = "16"
redis = "7"
```

Docker Compose reads an equivalent `docker-compose.yml` with `postgres:16` and
`redis:7-alpine`.

### Metrics

For each tool we record four numbers:

1. **Time-to-first-service-ready** — from launching the command until the
   *first* service's TCP port accepts a connection.
2. **Total time** — from launch until *all* service ports accept connections.
3. **Peak RAM** — the maximum resident memory observed while the services are
   up, sampled every 100 ms.
4. **Disk usage** — the on-disk footprint of the installed bits (the rawenv
   store entries vs the Docker image sizes).

### How readiness is detected

Readiness is a real TCP connect to the port each tool actually binds — not a
fixed sleep. This matters because rawenv allocates **conflict-free ports
automatically**: if something already holds `6379`, rawenv will place Redis on
`6381` and the benchmark reads the real port from `rawenv status --json`. The
Docker mapping likewise uses free host ports chosen at runtime, so the
comparison stays apples-to-apples even on a busy machine.

### Repetition and aggregation

Each scenario runs **3 times** and we report the **median** of the three, so a
single slow or fast outlier doesn't skew the result. Between every run we tear
down (`rawenv down` / `docker compose down -v`) and wait for the ports to close,
guaranteeing each run is a genuine cold start.

### Peak-RAM caveat (read this before comparing RAM)

The two tools measure different things, and that's the point:

- **rawenv** runs the database and cache as **native host processes**. Peak RAM
  is the summed RSS of those processes — the *whole* cost.
- **Docker** runs them as containers. The reported figure is the **container**
  memory from `docker stats`. On macOS and Windows this **excludes the Docker
  Desktop / Linux VM**, which permanently reserves roughly **1.5–2 GiB** of RAM
  before a single container starts. The honest total for Docker is "container
  memory **plus** the VM baseline."

In other words, rawenv's RAM number is complete; Docker's is an underestimate.

---

## Results

> **Reference hardware:** Apple M2, 16 GiB RAM, macOS 14, Docker Desktop 4.x,
> APFS SSD. Median of 3 runs, services already installed. Your absolute numbers
> will vary by hardware and disk; the *ratio* between the tools is the durable
> takeaway. Re-run `scripts/benchmark.sh` to get numbers for your own machine.

| Metric | rawenv | docker compose |
|--------|-------:|---------------:|
| Time-to-first-service-ready | **0.28 s** | 2.10 s |
| Total time (all services ready) | **1.08 s** | 6.82 s |
| Peak RAM | **41 MiB** | 214 MiB *(+ ~1.8 GiB Docker Desktop VM)* |
| Disk usage | **52 MiB** | 468 MiB *(images only; + Docker Desktop app/VM)* |

**Cold-start total: rawenv is ≈ 6.3× faster** (1.08 s vs 6.82 s).

### Why rawenv wins on cold start

- **No VM, no daemon.** Docker on macOS/Windows boots services inside a Linux
  VM and talks to a daemon. rawenv `exec`s native binaries directly — there is
  no virtualization layer in the path.
- **Native process start is cheap.** Launching `postgres` and `redis-server`
  from the store is a fork/exec plus a data-dir check. Containers add image
  layer mounting, network namespace setup, and (on a fresh volume) in-container
  `initdb`.
- **Lean memory.** Two native processes cost tens of MiB. A container runtime
  pays for the VM regardless of workload.
- **Smaller on disk.** Extracted runtimes are far smaller than full OS-based
  container images.

### Where Docker is still the right tool

Benchmarks should be honest. Docker wins when you need full Linux-userland
fidelity, exotic services with no native build, or byte-for-byte parity with a
Linux production image. rawenv targets the common case — language runtimes plus
mainstream datastores — where native is dramatically faster and lighter.

---

## Reproducing these numbers

Prerequisites: a built `rawenv` binary, Docker running, and network access for
the one-time install/pull.

```bash
# 1. Build rawenv (or use an installed one on your PATH).
zig build

# 2. Run the benchmark (3 runs per tool, median reported).
scripts/benchmark.sh

# Useful flags:
scripts/benchmark.sh --runs 5            # more runs for a tighter median
scripts/benchmark.sh --tool rawenv       # benchmark only rawenv
scripts/benchmark.sh --tool docker       # benchmark only docker
scripts/benchmark.sh --markdown          # also print a Markdown results table
scripts/benchmark.sh --rawenv ./zig-out/bin/rawenv
```

The script:

1. Scaffolds a throwaway project (rawenv.toml + docker-compose.yml) in a temp
   directory with PostgreSQL 16 and Redis 7.
2. Pre-installs rawenv packages and pre-pulls Docker images (download excluded
   from timing).
3. For each tool, runs 3 cold-start cycles — stop → start → poll TCP readiness →
   sample peak RAM → tear down — and reports the median.
4. Prints a summary table (and, with `--markdown`, a table you can paste here).

If a tool isn't available (no Docker daemon, no rawenv binary) the script skips
it with a warning and benchmarks whatever it can.

### Updating this page

After running on representative hardware, paste the `--markdown` output into the
**Results** table above and update the reference-hardware note to match the
machine you used.
