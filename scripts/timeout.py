#!/usr/bin/env python3
"""Run a command with a hard wall-clock timeout.

Kills the entire process group on timeout so spawned children (redis, postgres,
xcodebuild, etc.) are cleaned up too — not just the direct child. Exits 124 on
timeout (same convention as GNU `timeout`).

Usage: scripts/timeout.py <seconds> <command> [args...]
"""
import os, signal, subprocess, sys

if len(sys.argv) < 3:
    sys.exit("usage: timeout.py <seconds> <command> [args...]")

secs = float(sys.argv[1])
cmd = sys.argv[2:]
p = subprocess.Popen(cmd, start_new_session=True)  # child becomes group leader
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except ProcessLookupError:
            break
        try:
            p.wait(5)
            break
        except subprocess.TimeoutExpired:
            continue
    print(f"\n[timeout] killed `{cmd[0]}` after {secs:g}s", file=sys.stderr)
    sys.exit(124)
