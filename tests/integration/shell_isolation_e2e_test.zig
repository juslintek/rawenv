//! E2E-111 — `rawenv shell` environment isolation + cleanup.
//!
//! Drives the real `rawenv` binary against a temp project with an isolated
//! `$HOME`, and verifies that `rawenv shell`:
//!   1. Prepends `~/.rawenv/bin` to `PATH` so a rawenv-managed runtime wins
//!      (`command -v node` inside the shell resolves to the store's `node`).
//!   2. Exports the auto-generated connection strings (`DATABASE_URL`,
//!      `REDIS_URL`) derived from the project's services into the shell env.
//!   3. Leaves the *parent* process `PATH` unchanged and never contaminates it
//!      with the rawenv bin dir (the modification is scoped to the child).
//!   4. Spawns no background process: `rawenv shell` only `execve`s the user's
//!      shell in-process (no fork/daemon), so a clean exit + no service run
//!      state under the isolated `$HOME` proves nothing lingers.
//!   5. Works when the config relies on auto-generated connection strings
//!      (services declared with no explicit URL).
//!
//! How the in-shell environment is observed: `shell` `execve`s whatever `$SHELL`
//! points at, with *no* arguments — so it cannot be handed a `-c` script.
//! Instead the test points `$SHELL` at a small probe script that prints the
//! in-shell environment (PATH, DATABASE_URL, REDIS_URL, `command -v node`) and
//! exits. rawenv's process image is replaced by the probe, whose stdout (fd 1)
//! is captured by the parent. Temp dirs are removed via `cleanup()`.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;
const EnvMap = std.process.Environ.Map;

/// Resolve the rawenv binary under test (build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise).
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return "zig-out/bin/rawenv";
}

const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,

    fn deinit(self: RunResult) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }

    fn exitedWith(self: RunResult, code: u8) bool {
        return self.term == .exited and self.term.exited == code;
    }
};

/// Spawn the rawenv binary with the given args inside `dir`, using `env` (when
/// provided) as the child's complete environment.
fn run(argv: []const []const u8, dir: std.Io.Dir, env: ?*const EnvMap) !RunResult {
    const result = std.process.run(testing.allocator, io, .{
        .argv = argv,
        .cwd = .{ .dir = dir },
        .environ_map = env,
    }) catch |err| {
        std.debug.print("spawn error running {s}: {}\n", .{ argv[0], err });
        return err;
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

/// `testing.tmpDir` creates `<cwd>/.zig-cache/tmp/<sub_path>`; build that
/// absolute path so it can be handed to the child as `$HOME` (Io.Dir has no
/// realpath in this Zig version).
fn absHome(allocator: std.mem.Allocator, sub_path: []const u8) ![]u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    return std.fmt.allocPrint(allocator, "{s}/.zig-cache/tmp/{s}", .{ cwd, sub_path });
}

/// True when an absolute path exists (file, dir, or symlink).
fn pathExistsAbs(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 0) == 0;
}

/// `mkdir(path, 0755)` on an absolute path (idempotent — pre-existing is fine).
fn mkdirAbs(path: []const u8) void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = std.c.mkdir(z, 0o755);
}

/// `chmod(path, 0755)` on an absolute path so it is executable.
fn chmodExecAbs(path: []const u8) void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = std.c.chmod(z, 0o755);
}

/// Extract the value following `prefix` up to the end of its line. Used to read
/// the probe script's `KEY=value` output lines out of captured stdout.
fn fieldAfter(stdout: []const u8, prefix: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, stdout, prefix) orelse return null;
    const start = at + prefix.len;
    var end = start;
    while (end < stdout.len and stdout[end] != '\n' and stdout[end] != '\r') : (end += 1) {}
    return stdout[start..end];
}

test "rawenv shell isolates env and leaves no side effects" {
    // `rawenv shell` activation is POSIX-only (execve of $SHELL); on Windows the
    // command is a no-op, so there is nothing to assert.
    if (comptime builtin.os.tag == .windows) return error.SkipZigTest;

    const a = testing.allocator;

    // ── Isolated $HOME with a rawenv-managed `node` so PATH wins are visible ──
    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absHome(a, &home_tmp.sub_path);
    defer a.free(home);

    const rawenv_dir = try std.fmt.allocPrint(a, "{s}/.rawenv", .{home});
    defer a.free(rawenv_dir);
    const bin_dir = try std.fmt.allocPrint(a, "{s}/.rawenv/bin", .{home});
    defer a.free(bin_dir);
    mkdirAbs(rawenv_dir);
    mkdirAbs(bin_dir);

    // A `node` stub in ~/.rawenv/bin — content is irrelevant; it only has to be
    // an executable on PATH so `command -v node` resolves to this exact path.
    try home_tmp.dir.writeFile(io, .{ .sub_path = ".rawenv/bin/node", .data = "#!/bin/sh\nexit 0\n" });
    const node_path = try std.fmt.allocPrint(a, "{s}/node", .{bin_dir});
    defer a.free(node_path);
    chmodExecAbs(node_path);

    // Probe script: rawenv `execve`s this as $SHELL. It prints the in-shell
    // environment so the parent can assert on it, then exits 0.
    try home_tmp.dir.writeFile(io, .{
        .sub_path = "probe.sh",
        .data =
        \\#!/bin/sh
        \\printf 'RAWENV_PROBE_WHICH=%s\n' "$(command -v node)"
        \\printf 'RAWENV_PROBE_DB=%s\n' "$DATABASE_URL"
        \\printf 'RAWENV_PROBE_RD=%s\n' "$REDIS_URL"
        \\printf 'RAWENV_PROBE_ACTIVE=%s\n' "$RAWENV_ACTIVE"
        \\printf 'RAWENV_PROBE_PATH=%s\n' "$PATH"
        \\exit 0
        \\
        ,
    });
    const probe_path = try std.fmt.allocPrint(a, "{s}/probe.sh", .{home});
    defer a.free(probe_path);
    chmodExecAbs(probe_path);

    // ── Project whose services yield auto-generated connection strings ───────
    var proj = testing.tmpDir(.{});
    defer proj.cleanup();
    try proj.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data =
        \\[project]
        \\name = "e2e-shell"
        \\
        \\[runtimes]
        \\node = "22"
        \\
        \\[services]
        \\postgresql = "16"
        \\redis = "7"
        \\
        \\[detect]
        \\auto = true
        \\
        ,
    });

    // Capture the parent's PATH so we can prove `shell` doesn't mutate it.
    const parent_path_before = blk: {
        const p = std.c.getenv("PATH") orelse break :blk try a.dupe(u8, "");
        break :blk try a.dupe(u8, std.mem.sliceTo(p, 0));
    };
    defer a.free(parent_path_before);

    // Child env: inherit PATH (so /bin/sh, printf, command resolve), pin HOME to
    // the isolated store, and point SHELL at the probe script.
    var env = EnvMap.init(a);
    defer env.deinit();
    try env.put("PATH", parent_path_before);
    try env.put("HOME", home);
    try env.put("SHELL", probe_path);

    const r = try run(&.{ rawenvBin(), "shell" }, proj.dir, &env);
    defer r.deinit();

    // ── 4. No background process: shell only execs in-process and returns. ───
    // `std.process.run` waits for and reaps the child, so a clean `.exited` with
    // the probe's own exit code (0) proves nothing forked/daemonized or hung.
    try testing.expect(r.term == .exited);
    try testing.expect(r.exitedWith(0));

    // The banner is written straight to fd 1 (unbuffered) before the execve, so
    // it survives into captured stdout and proves we entered this project.
    try testing.expect(contains(r.stdout, "Entering rawenv shell"));
    try testing.expect(contains(r.stdout, "e2e-shell"));

    // ── 1. PATH adds ~/.rawenv/bin (verified via `command -v node`). ─────────
    const which = fieldAfter(r.stdout, "RAWENV_PROBE_WHICH=") orelse {
        std.debug.print("no probe output; stdout:\n{s}\nstderr:\n{s}\n", .{ r.stdout, r.stderr });
        return error.NoProbeOutput;
    };
    try testing.expectEqualStrings(node_path, which);

    const in_path = fieldAfter(r.stdout, "RAWENV_PROBE_PATH=") orelse return error.NoProbeOutput;
    try testing.expect(std.mem.startsWith(u8, in_path, bin_dir));

    // ── 2/5. Auto-generated connection strings are set inside the shell. ─────
    const db = fieldAfter(r.stdout, "RAWENV_PROBE_DB=") orelse return error.NoProbeOutput;
    try testing.expectEqualStrings("postgresql://localhost:5432", db);
    const rd = fieldAfter(r.stdout, "RAWENV_PROBE_RD=") orelse return error.NoProbeOutput;
    try testing.expectEqualStrings("redis://localhost:6379", rd);
    const active = fieldAfter(r.stdout, "RAWENV_PROBE_ACTIVE=") orelse return error.NoProbeOutput;
    try testing.expectEqualStrings("1", active);

    // ── 3. Parent PATH unchanged + never contaminated by the rawenv bin dir. ─
    const parent_path_after = blk: {
        const p = std.c.getenv("PATH") orelse break :blk "";
        break :blk std.mem.sliceTo(p, 0);
    };
    try testing.expectEqualStrings(parent_path_before, parent_path_after);
    try testing.expect(std.mem.indexOf(u8, parent_path_after, bin_dir) == null);

    // ── 4 (cont). No service run state was created under the isolated HOME. ──
    // `shell` reads config and execs a shell; it must never start a service, so
    // the per-project run/data/log dirs must not appear.
    for ([_][]const u8{ "run", "data", "logs", "services" }) |sub| {
        const p = try std.fmt.allocPrint(a, "{s}/.rawenv/{s}", .{ home, sub });
        defer a.free(p);
        try testing.expect(!pathExistsAbs(p));
    }
}
