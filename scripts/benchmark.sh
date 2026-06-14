#!/usr/bin/env bash
#
# benchmark.sh — cold-start benchmark: `rawenv up` vs `docker compose up`.
#
# Measures, on the SAME project (PostgreSQL 16 + Redis 7), how long each tool
# takes to go from a fully stopped state to "services responding", plus the
# peak RAM and on-disk footprint each approach uses. Runs every scenario three
# times (by default) and reports the median so a single slow run does not skew
# the result.
#
# The benchmark measures *startup*, not *download*: it pre-installs the rawenv
# packages and pre-pulls the Docker images before timing begins. That is the
# fair, steady-state "I open my laptop and start working" comparison.
#
# Metrics per tool (median of N runs):
#   * time-to-first-service-ready  — launch → first service port accepts TCP
#   * total time                   — launch → ALL service ports accept TCP
#   * peak RAM                      — max resident memory observed while up
#   * disk usage                    — on-disk footprint of the installed bits
#
# Readiness is measured by polling the TCP port each tool actually binds.
# rawenv allocates conflict-free ports automatically (read from
# `rawenv status --json`); the Docker mapping uses free host ports chosen at
# runtime. This keeps the comparison apples-to-apples even when something else
# already occupies 5432/6379 on the host.
#
# Usage:
#   scripts/benchmark.sh [options]
#
# Options:
#   --runs N        Number of timed runs per tool (default: 3).
#   --tool WHICH    both | rawenv | docker (default: both).
#   --rawenv PATH   Path to the rawenv binary (default: from PATH, then
#                   ./zig-out/bin/rawenv, then ~/.rawenv/bin/rawenv).
#   --markdown      Also emit a Markdown results table (for docs/benchmarks.md).
#   --keep          Keep the temporary project directory for inspection.
#   -h, --help      Show this help.
#
# Exit status is 0 when at least one tool was benchmarked successfully.
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
RUNS=3
TOOL="both"
EMIT_MARKDOWN=0
KEEP_TMP=0
RAWENV_BIN=""
READY_TIMEOUT_MS=60000

# Docker host ports (chosen at runtime to avoid conflicts).
DOCKER_PG_PORT=5432
DOCKER_REDIS_PORT=6379
# rawenv-assigned ports (read from `rawenv status --json`).
RAWENV_PG_PORT=5432
RAWENV_REDIS_PORT=6379

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)
      RUNS="${2:?--runs needs a value}"
      shift 2
      ;;
    --tool)
      TOOL="${2:?--tool needs a value}"
      shift 2
      ;;
    --rawenv)
      RAWENV_BIN="${2:?--rawenv needs a value}"
      shift 2
      ;;
    --markdown)
      EMIT_MARKDOWN=1
      shift
      ;;
    --keep)
      KEEP_TMP=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Portable helpers
# ----------------------------------------------------------------------------

# now_ms — current wall-clock time in integer milliseconds. BSD `date` has no
# %N, so prefer python3, then perl, then fall back to second precision.
if command -v python3 >/dev/null 2>&1; then
  now_ms() { python3 -c 'import time;print(int(time.time()*1000))'; }
elif command -v perl >/dev/null 2>&1; then
  now_ms() { perl -MTime::HiRes=time -e 'print int(time()*1000)'; }
else
  now_ms() { echo $(($(date +%s) * 1000)); }
fi

# port_open HOST PORT — return 0 if a TCP connection succeeds, else 1.
# Uses bash's /dev/tcp so no nc/netcat dependency is required.
port_open() {
  (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null && exec 3>&- 2>/dev/null
}

# find_free_port START — echo the first free TCP port at or above START.
find_free_port() {
  local p="$1"
  while port_open 127.0.0.1 "$p"; do p=$((p + 1)); done
  echo "$p"
}

# median_portable — read newline-separated numbers on stdin, print the median
# (middle of the sorted list; lower-middle for an even count). No gawk needed.
median_portable() {
  sort -n | awk '{ a[NR]=$1 } END { if (NR==0){print 0} else {print a[int((NR+1)/2)]} }'
}

# ms_to_s — pretty-print integer milliseconds as seconds with 2 decimals.
ms_to_s() { awk -v ms="$1" 'BEGIN { printf "%.2f", ms/1000 }'; }
# kb_to_mb — pretty-print integer kilobytes as MiB with 1 decimal.
kb_to_mb() { awk -v kb="$1" 'BEGIN { printf "%.1f", kb/1024 }'; }

log() { printf '%s\n' "$*" >&2; }
step() { printf '\n==> %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# Tool discovery
# ----------------------------------------------------------------------------
resolve_rawenv() {
  if [ -n "$RAWENV_BIN" ]; then
    echo "$RAWENV_BIN"
    return
  fi
  if command -v rawenv >/dev/null 2>&1; then
    command -v rawenv
    return
  fi
  if [ -x "./zig-out/bin/rawenv" ]; then
    echo "$PWD/zig-out/bin/rawenv"
    return
  fi
  if [ -x "$HOME/.rawenv/bin/rawenv" ]; then
    echo "$HOME/.rawenv/bin/rawenv"
    return
  fi
  echo ""
}

# docker_compose — print the working compose invocation ("docker compose" or
# the legacy "docker-compose"), or nothing if neither works.
docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi
  echo ""
}

# ----------------------------------------------------------------------------
# Test project scaffolding
# ----------------------------------------------------------------------------
TMP_PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/rawenv-bench.XXXXXX")"
COMPOSE_PROJECT="rawenvbench"

cleanup() {
  if [ -n "${RAWENV:-}" ]; then (cd "$TMP_PROJECT" 2>/dev/null && "$RAWENV" down >/dev/null 2>&1 || true); fi
  if [ -n "${DC:-}" ]; then (cd "$TMP_PROJECT" 2>/dev/null && $DC -p "$COMPOSE_PROJECT" down -v >/dev/null 2>&1 || true); fi
  if [ "$KEEP_TMP" -eq 1 ]; then log "Kept temporary project at: $TMP_PROJECT"; else rm -rf "$TMP_PROJECT"; fi
}
trap cleanup EXIT INT TERM

scaffold_rawenv() {
  cat >"$TMP_PROJECT/rawenv.toml" <<EOF
[project]
name = "rawenv-bench"

[services]
postgresql = "16"
redis = "7"
EOF
}

scaffold_compose() {
  cat >"$TMP_PROJECT/docker-compose.yml" <<EOF
services:
  postgresql:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: rawenv
    ports:
      - "${DOCKER_PG_PORT}:5432"
  redis:
    image: redis:7-alpine
    ports:
      - "${DOCKER_REDIS_PORT}:6379"
EOF
}

# rawenv_resolve_ports — parse `rawenv status --json` for the ports rawenv
# assigned to postgresql and redis, updating the globals.
rawenv_resolve_ports() {
  local json
  json="$(cd "$TMP_PROJECT" && "$RAWENV" status --json 2>/dev/null || true)"
  [ -z "$json" ] && return 0
  if command -v python3 >/dev/null 2>&1; then
    local out
    out="$(printf '%s' "$json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
pg = rd = ""
for s in d.get("services", []):
    if s.get("name","").startswith("postgres"): pg = s.get("port","")
    if s.get("name","").startswith("redis"): rd = s.get("port","")
print(pg, rd)
')"
    local pg rd
    pg="$(echo "$out" | awk '{print $1}')"
    rd="$(echo "$out" | awk '{print $2}')"
    [ -n "$pg" ] && RAWENV_PG_PORT="$pg"
    [ -n "$rd" ] && RAWENV_REDIS_PORT="$rd"
  fi
}

# ----------------------------------------------------------------------------
# Readiness polling
# ----------------------------------------------------------------------------
# wait_ready START_MS MODE PORT1 PORT2 ... — poll the given ports until ready.
#   MODE=first → return as soon as ANY listed port is open.
#   MODE=all   → return once ALL listed ports are open.
# Echoes elapsed milliseconds since START_MS. Returns 1 on timeout.
wait_ready() {
  local start_ms="$1" mode="$2"
  shift 2
  local ports=("$@")
  local deadline=$(($(now_ms) + READY_TIMEOUT_MS))
  while [ "$(now_ms)" -lt "$deadline" ]; do
    local open=0 total=0 p
    for p in "${ports[@]}"; do
      total=$((total + 1))
      port_open 127.0.0.1 "$p" && open=$((open + 1))
    done
    if [ "$mode" = "first" ]; then
      [ "$open" -ge 1 ] && {
        echo $(($(now_ms) - start_ms))
        return 0
      }
    else
      [ "$open" -ge "$total" ] && {
        echo $(($(now_ms) - start_ms))
        return 0
      }
    fi
    sleep 0.05
  done
  echo $(($(now_ms) - start_ms))
  return 1
}

# wait_ports_closed PORT... — block until none of the given ports accept TCP.
wait_ports_closed() {
  local p any
  while :; do
    any=0
    for p in "$@"; do port_open 127.0.0.1 "$p" && any=1; done
    [ "$any" -eq 0 ] && break
    sleep 0.1
  done
}

# ----------------------------------------------------------------------------
# Peak-RAM sampling (background)
# ----------------------------------------------------------------------------
# sample_peak OUT_FILE STOP_FILE TOOL — sample a memory metric every 100ms and
# write the running maximum (KB) to OUT_FILE until STOP_FILE appears.
sample_peak() {
  local out_file="$1" stop_file="$2" tool="$3"
  local peak=0 cur=0
  while [ ! -f "$stop_file" ]; do
    if [ "$tool" = "rawenv" ]; then
      # Sum RSS (KB) of native service processes launched from the rawenv store.
      cur="$(ps -axo rss=,command= 2>/dev/null |
        awk '/\.rawenv\/store/ && (/postgres/ || /redis-server/) { s+=$1 } END { print s+0 }')"
    else
      # Sum container memory (→KB) reported by docker stats for this project.
      local ids
      ids="$(docker ps -q --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" 2>/dev/null)"
      if [ -n "$ids" ]; then
        cur="$(docker stats --no-stream --format '{{.MemUsage}}' $ids 2>/dev/null |
          awk '{ v=$1; u=$1;
                   sub(/[0-9.]+/,"",u); sub(/[A-Za-z].*/,"",v);
                   mult=1; if(u ~ /GiB/) mult=1024*1024; else if(u ~ /MiB/) mult=1024; else if(u ~ /KiB/) mult=1; else mult=1/1024;
                   s+=v*mult } END { print int(s+0) }')"
      else
        cur=0
      fi
    fi
    [ -z "$cur" ] && cur=0
    if [ "$cur" -gt "$peak" ] 2>/dev/null; then peak="$cur"; fi
    sleep 0.1
  done
  echo "$peak" >"$out_file"
}

# ----------------------------------------------------------------------------
# Disk-usage measurement (KB)
# ----------------------------------------------------------------------------
disk_rawenv_kb() {
  local store="$HOME/.rawenv/store" total=0 d sz
  for d in "$store"/postgres* "$store"/redis*; do
    [ -d "$d" ] || continue
    sz="$(du -sk "$d" 2>/dev/null | awk '{print $1}')"
    [ -n "$sz" ] && total=$((total + sz))
  done
  echo "$total"
}

disk_docker_kb() {
  local total=0 img bytes
  for img in postgres:16 redis:7-alpine; do
    bytes="$(docker image inspect "$img" --format '{{.Size}}' 2>/dev/null || echo 0)"
    [ -z "$bytes" ] && bytes=0
    total=$((total + bytes / 1024))
  done
  echo "$total"
}

# ----------------------------------------------------------------------------
# Per-tool benchmark drivers
# ----------------------------------------------------------------------------
RAWENV_FIRST_MS=0
RAWENV_TOTAL_MS=0
RAWENV_PEAK_KB=0
RAWENV_DISK_KB=0
RAWENV_OK=0
DOCKER_FIRST_MS=0
DOCKER_TOTAL_MS=0
DOCKER_PEAK_KB=0
DOCKER_DISK_KB=0
DOCKER_OK=0

# run_once TOOL — one cold-start cycle. Echoes "FIRST_MS TOTAL_MS PEAK_KB".
run_once() {
  local tool="$1"
  local stop_file="$TMP_PROJECT/.stop.$$" peak_file="$TMP_PROJECT/.peak.$$"
  rm -f "$stop_file" "$peak_file"

  local ports
  if [ "$tool" = "rawenv" ]; then
    ports=("$RAWENV_PG_PORT" "$RAWENV_REDIS_PORT")
  else ports=("$DOCKER_PG_PORT" "$DOCKER_REDIS_PORT"); fi

  # Cold state: ensure everything is stopped before timing.
  (
    cd "$TMP_PROJECT"
    if [ "$tool" = "rawenv" ]; then
      "$RAWENV" down >/dev/null 2>&1 || true
    else $DC -p "$COMPOSE_PROJECT" down -v >/dev/null 2>&1 || true; fi
  )
  wait_ports_closed "${ports[@]}"

  sample_peak "$peak_file" "$stop_file" "$tool" &
  local sampler_pid=$!

  local start_ms first_ms total_ms
  start_ms="$(now_ms)"
  (
    cd "$TMP_PROJECT"
    if [ "$tool" = "rawenv" ]; then
      "$RAWENV" up >/dev/null 2>&1 || true
    else $DC -p "$COMPOSE_PROJECT" up -d >/dev/null 2>&1 || true; fi
  )

  first_ms="$(wait_ready "$start_ms" first "${ports[@]}")" || true
  total_ms="$(wait_ready "$start_ms" all "${ports[@]}")" || true

  touch "$stop_file"
  wait "$sampler_pid" 2>/dev/null || true
  local peak_kb=0
  [ -f "$peak_file" ] && peak_kb="$(cat "$peak_file")"
  rm -f "$stop_file" "$peak_file"

  # Tear down for the next iteration.
  (
    cd "$TMP_PROJECT"
    if [ "$tool" = "rawenv" ]; then
      "$RAWENV" down >/dev/null 2>&1 || true
    else $DC -p "$COMPOSE_PROJECT" down -v >/dev/null 2>&1 || true; fi
  )

  echo "$first_ms $total_ms $peak_kb"
}

run_tool() {
  local tool="$1"
  step "Benchmarking: $tool ($RUNS runs)"
  local firsts="" totals="" peaks="" i out f t p
  for i in $(seq 1 "$RUNS"); do
    out="$(run_once "$tool")"
    f="$(echo "$out" | awk '{print $1}')"
    t="$(echo "$out" | awk '{print $2}')"
    p="$(echo "$out" | awk '{print $3}')"
    log "  run $i: first=$(ms_to_s "$f")s total=$(ms_to_s "$t")s peak=$(kb_to_mb "$p")MiB"
    firsts="$firsts$f
"
    totals="$totals$t
"
    peaks="$peaks$p
"
  done
  local m_first m_total m_peak
  m_first="$(printf '%s' "$firsts" | grep -v '^$' | median_portable)"
  m_total="$(printf '%s' "$totals" | grep -v '^$' | median_portable)"
  m_peak="$(printf '%s' "$peaks" | grep -v '^$' | median_portable)"

  if [ "$tool" = "rawenv" ]; then
    RAWENV_FIRST_MS="$m_first"
    RAWENV_TOTAL_MS="$m_total"
    RAWENV_PEAK_KB="$m_peak"
    RAWENV_DISK_KB="$(disk_rawenv_kb)"
    RAWENV_OK=1
  else
    DOCKER_FIRST_MS="$m_first"
    DOCKER_TOTAL_MS="$m_total"
    DOCKER_PEAK_KB="$m_peak"
    DOCKER_DISK_KB="$(disk_docker_kb)"
    DOCKER_OK=1
  fi
}

# ----------------------------------------------------------------------------
# Pre-warm: install/pull so timing measures startup, not download.
# ----------------------------------------------------------------------------
prewarm_rawenv() {
  step "Pre-installing rawenv packages (postgresql@16, redis@7)"
  (
    cd "$TMP_PROJECT"
    "$RAWENV" add postgresql@16 >/dev/null 2>&1 || true
    "$RAWENV" add redis@7 >/dev/null 2>&1 || true
  )
}

prewarm_docker() {
  step "Pre-pulling Docker images (postgres:16, redis:7-alpine)"
  docker pull postgres:16 >/dev/null 2>&1 || true
  docker pull redis:7-alpine >/dev/null 2>&1 || true
}

# ----------------------------------------------------------------------------
# Reporting
# ----------------------------------------------------------------------------
print_summary() {
  printf '\n'
  printf '============================================================\n'
  printf ' Cold-start benchmark — median of %s runs\n' "$RUNS"
  printf '============================================================\n'
  printf '%-26s %12s %12s\n' "Metric" "rawenv" "docker"
  printf '%-26s %12s %12s\n' "--------------------------" "------------" "------------"

  local rf rt rp rd df dt dp dd
  rf=$([ "$RAWENV_OK" -eq 1 ] && ms_to_s "$RAWENV_FIRST_MS" || echo "n/a")
  rt=$([ "$RAWENV_OK" -eq 1 ] && ms_to_s "$RAWENV_TOTAL_MS" || echo "n/a")
  rp=$([ "$RAWENV_OK" -eq 1 ] && kb_to_mb "$RAWENV_PEAK_KB" || echo "n/a")
  rd=$([ "$RAWENV_OK" -eq 1 ] && kb_to_mb "$RAWENV_DISK_KB" || echo "n/a")
  df=$([ "$DOCKER_OK" -eq 1 ] && ms_to_s "$DOCKER_FIRST_MS" || echo "n/a")
  dt=$([ "$DOCKER_OK" -eq 1 ] && ms_to_s "$DOCKER_TOTAL_MS" || echo "n/a")
  dp=$([ "$DOCKER_OK" -eq 1 ] && kb_to_mb "$DOCKER_PEAK_KB" || echo "n/a")
  dd=$([ "$DOCKER_OK" -eq 1 ] && kb_to_mb "$DOCKER_DISK_KB" || echo "n/a")

  printf '%-26s %12s %12s\n' "time-to-first-ready (s)" "$rf" "$df"
  printf '%-26s %12s %12s\n' "total time (s)" "$rt" "$dt"
  printf '%-26s %12s %12s\n' "peak RAM (MiB)" "$rp" "$dp"
  printf '%-26s %12s %12s\n' "disk usage (MiB)" "$rd" "$dd"
  printf '============================================================\n'

  if [ "$RAWENV_OK" -eq 1 ] && [ "$DOCKER_OK" -eq 1 ] && [ "$DOCKER_TOTAL_MS" -gt 0 ] && [ "$RAWENV_TOTAL_MS" -gt 0 ]; then
    local speedup
    speedup="$(awk -v d="$DOCKER_TOTAL_MS" -v r="$RAWENV_TOTAL_MS" 'BEGIN { printf "%.1f", d/r }')"
    printf '\nrawenv total cold-start is %sx faster than docker compose.\n' "$speedup"
  fi
}

print_markdown() {
  [ "$EMIT_MARKDOWN" -eq 1 ] || return 0
  printf '\n--- Markdown (for docs/benchmarks.md) ---\n\n'
  printf '| Metric | rawenv | docker compose |\n'
  printf '|--------|-------:|---------------:|\n'
  printf '| Time-to-first-service-ready | %s s | %s s |\n' \
    "$([ "$RAWENV_OK" -eq 1 ] && ms_to_s "$RAWENV_FIRST_MS" || echo n/a)" \
    "$([ "$DOCKER_OK" -eq 1 ] && ms_to_s "$DOCKER_FIRST_MS" || echo n/a)"
  printf '| Total time (all services) | %s s | %s s |\n' \
    "$([ "$RAWENV_OK" -eq 1 ] && ms_to_s "$RAWENV_TOTAL_MS" || echo n/a)" \
    "$([ "$DOCKER_OK" -eq 1 ] && ms_to_s "$DOCKER_TOTAL_MS" || echo n/a)"
  printf '| Peak RAM | %s MiB | %s MiB |\n' \
    "$([ "$RAWENV_OK" -eq 1 ] && kb_to_mb "$RAWENV_PEAK_KB" || echo n/a)" \
    "$([ "$DOCKER_OK" -eq 1 ] && kb_to_mb "$DOCKER_PEAK_KB" || echo n/a)"
  printf '| Disk usage | %s MiB | %s MiB |\n' \
    "$([ "$RAWENV_OK" -eq 1 ] && kb_to_mb "$RAWENV_DISK_KB" || echo n/a)" \
    "$([ "$DOCKER_OK" -eq 1 ] && kb_to_mb "$DOCKER_DISK_KB" || echo n/a)"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  step "rawenv cold-start benchmark"

  local want_rawenv=0 want_docker=0
  case "$TOOL" in
    both)
      want_rawenv=1
      want_docker=1
      ;;
    rawenv) want_rawenv=1 ;;
    docker) want_docker=1 ;;
    *)
      echo "Invalid --tool: $TOOL (use both|rawenv|docker)" >&2
      exit 2
      ;;
  esac

  RAWENV="$(resolve_rawenv)"
  DC="$(docker_compose)"

  if [ "$want_rawenv" -eq 1 ] && [ -z "$RAWENV" ]; then
    log "WARNING: rawenv binary not found — skipping rawenv benchmark."
    log "         Build it with \`zig build\` or pass --rawenv PATH."
    want_rawenv=0
  fi
  if [ "$want_docker" -eq 1 ]; then
    if [ -z "$DC" ]; then
      log "WARNING: docker compose not available — skipping docker benchmark."
      want_docker=0
    elif ! docker info >/dev/null 2>&1; then
      log "WARNING: docker daemon not running — skipping docker benchmark."
      want_docker=0
    fi
  fi

  if [ "$want_rawenv" -eq 0 ] && [ "$want_docker" -eq 0 ]; then
    log "ERROR: no tools available to benchmark."
    exit 1
  fi

  scaffold_rawenv
  if [ "$want_rawenv" -eq 1 ]; then
    rawenv_resolve_ports
  fi
  if [ "$want_docker" -eq 1 ]; then
    DOCKER_PG_PORT="$(find_free_port 5432)"
    DOCKER_REDIS_PORT="$(find_free_port $((DOCKER_PG_PORT > 6379 ? DOCKER_PG_PORT + 1 : 6379)))"
    scaffold_compose
  fi

  log "Test project: $TMP_PROJECT"
  [ "$want_rawenv" -eq 1 ] && log "rawenv ports:  postgresql=$RAWENV_PG_PORT redis=$RAWENV_REDIS_PORT"
  [ "$want_docker" -eq 1 ] && log "docker ports:  postgresql=$DOCKER_PG_PORT redis=$DOCKER_REDIS_PORT"

  [ "$want_rawenv" -eq 1 ] && prewarm_rawenv
  [ "$want_docker" -eq 1 ] && prewarm_docker

  [ "$want_rawenv" -eq 1 ] && run_tool rawenv
  [ "$want_docker" -eq 1 ] && run_tool docker

  print_summary
  print_markdown
}

main "$@"
