//! E2E-109 — `rawenv uninstall` removes everything cleanly.
//!
//! Drives the real `rawenv` binary against a fully isolated `$HOME` so the
//! assertions never touch the developer's actual machine. The test seeds every
//! artifact rawenv can leave behind, runs `rawenv uninstall --force`, and then
//! verifies — via the filesystem and the process list — that nothing remains:
//!
//!   • `~/.rawenv/` (store, bin symlinks, data dirs) is gone.
//!   • PATH symlinks under `~/.rawenv/bin/` are gone.
//!   • No launchd plists with the `com.rawenv.` prefix remain in
//!     `~/Library/LaunchAgents/` (macOS).
//!   • No systemd units with the `rawenv-` prefix remain in
//!     `~/.config/systemd/user/` (Linux).
//!   • Unrelated plists / units are left untouched (uninstall is surgical).
//!   • No rawenv-managed process tied to the isolated HOME is still running.
//!
//! The isolated HOME path follows the same construction used by the other
//! integration tests: testing.tmpDir() creates `<cwd>/.zig-cache/tmp/<sub>`.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;
const EnvMap = std.process.Environ.Map;

/// Resolve the rawenv binary under test (build wiring sets RAWENV_BIN).
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
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

// ── POSIX filesystem helpers (absolute paths; mirror production std.c usage) ──

/// `mkdir -p` for an absolute path.
fn mkdirP(path: []const u8) void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i] == '/') {
            const z = std.fmt.bufPrintZ(&buf, "{s}", .{path[0..i]}) catch return;
            _ = std.c.mkdir(z, 0o755);
        }
    }
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = std.c.mkdir(z, 0o755);
}

fn writeFileAbs(path: []const u8, content: []const u8) !void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = try std.fmt.bufPrintZ(&buf, "{s}", .{path});
    const fd = try std.posix.openat(std.posix.AT.FDCWD, std.mem.sliceTo(z, 0), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.c.close(fd);
    var written: usize = 0;
    while (written < content.len) {
        const n = std.c.write(fd, content.ptr + written, content.len - written);
        if (n < 0) return error.WriteFailed;
        written += @intCast(n);
    }
}

fn symlinkAbs(target: []const u8, link: []const u8) void {
    var tb: [std.fs.max_path_bytes]u8 = undefined;
    var lb: [std.fs.max_path_bytes]u8 = undefined;
    const tz = std.fmt.bufPrintZ(&tb, "{s}", .{target}) catch return;
    const lz = std.fmt.bufPrintZ(&lb, "{s}", .{link}) catch return;
    _ = std.c.symlink(tz, lz);
}

/// True when a path exists (file, directory, or symlink — uses lstat-style
/// access so a dangling symlink target does not matter for presence).
fn pathExists(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 0) == 0;
}

/// True for a symlink specifically, even when its target is gone.
fn isSymlink(path: []const u8) bool {
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&pbuf, "{s}", .{path}) catch return false;
    // readlink succeeds (>= 0) only for a symlink; non-symlinks fail with EINVAL.
    var tbuf: [std.fs.max_path_bytes]u8 = undefined;
    return std.c.readlink(z, &tbuf, tbuf.len) >= 0;
}

fn join(parts: []const []const u8) ![]u8 {
    return std.fs.path.join(testing.allocator, parts);
}

test "uninstall --force removes every rawenv artifact cleanly (E2E-109)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const a = testing.allocator;

    // Isolated HOME — never the developer's real home dir.
    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    const home = try std.fmt.allocPrint(a, "{s}/.zig-cache/tmp/{s}", .{ cwd, home_tmp.sub_path });
    defer a.free(home);

    // ── Seed artifacts ───────────────────────────────────────────────────────
    // Store runtime + binary.
    const store_bin_dir = try join(&.{ home, ".rawenv", "store", "node-22", "bin" });
    defer a.free(store_bin_dir);
    mkdirP(store_bin_dir);
    const store_node = try join(&.{ store_bin_dir, "node" });
    defer a.free(store_node);
    try writeFileAbs(store_node, "#!/bin/sh\necho node\n");

    // bin/ PATH symlink → store binary.
    const bin_dir = try join(&.{ home, ".rawenv", "bin" });
    defer a.free(bin_dir);
    mkdirP(bin_dir);
    const bin_symlink = try join(&.{ bin_dir, "node" });
    defer a.free(bin_symlink);
    symlinkAbs(store_node, bin_symlink);
    try testing.expect(isSymlink(bin_symlink)); // sanity: symlink really created

    // Per-project data dir.
    const data_dir = try join(&.{ home, ".rawenv", "data", "deadbeef", "redis" });
    defer a.free(data_dir);
    mkdirP(data_dir);
    const data_file = try join(&.{ data_dir, "dump.rdb" });
    defer a.free(data_file);
    try writeFileAbs(data_file, "x");

    // OS service unit + an unrelated control unit that must survive uninstall.
    var rawenv_unit: []u8 = undefined; // freed below
    var control_unit: []u8 = undefined;
    if (builtin.os.tag == .macos) {
        const agents = try join(&.{ home, "Library", "LaunchAgents" });
        defer a.free(agents);
        mkdirP(agents);
        rawenv_unit = try join(&.{ agents, "com.rawenv.redis.plist" });
        control_unit = try join(&.{ agents, "com.example.other.plist" });
    } else {
        const units = try join(&.{ home, ".config", "systemd", "user" });
        defer a.free(units);
        mkdirP(units);
        rawenv_unit = try join(&.{ units, "rawenv-redis.service" });
        control_unit = try join(&.{ units, "other.service" });
    }
    defer a.free(rawenv_unit);
    defer a.free(control_unit);
    try writeFileAbs(rawenv_unit, "# rawenv-managed unit\n");
    try writeFileAbs(control_unit, "# unrelated unit\n");

    // Confirm the world we built actually exists before uninstalling.
    const rawenv_root = try join(&.{ home, ".rawenv" });
    defer a.free(rawenv_root);
    try testing.expect(pathExists(rawenv_root));
    try testing.expect(pathExists(rawenv_unit));
    try testing.expect(pathExists(control_unit));

    // ── Run uninstall --force in the isolated HOME ───────────────────────────
    var env = EnvMap.init(a);
    defer env.deinit();
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home);

    {
        const r = try run(&.{ rawenvBin(), "uninstall", "--force" }, home_tmp.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(contains(r.stdout, "rawenv uninstalled"));
        // --force must not block on a prompt.
        try testing.expect(!contains(r.stdout, "Proceed?"));
    }

    // ── Assertions: nothing rawenv left behind ───────────────────────────────
    // ~/.rawenv/ (store, data dirs) is gone, including the bin/ symlink.
    try testing.expect(!pathExists(rawenv_root));
    try testing.expect(!pathExists(bin_dir));
    try testing.expect(!pathExists(bin_symlink));
    try testing.expect(!isSymlink(bin_symlink));
    try testing.expect(!pathExists(store_node));
    try testing.expect(!pathExists(data_dir));

    // The rawenv-prefixed OS unit is removed; the unrelated one is preserved.
    try testing.expect(!pathExists(rawenv_unit));
    try testing.expect(pathExists(control_unit));

    // Process list: no rawenv-managed process tied to this isolated HOME runs.
    {
        const r = try run(&.{ "/bin/ps", "ax" }, home_tmp.dir, &env);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        // Nothing referencing the isolated store/data should be alive.
        const needle = try join(&.{ home, ".rawenv" });
        defer a.free(needle);
        try testing.expect(!contains(r.stdout, needle));
    }
}

test "uninstall --force is idempotent on an already-clean HOME (E2E-109)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const a = testing.allocator;

    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.NoCwd;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    const home = try std.fmt.allocPrint(a, "{s}/.zig-cache/tmp/{s}", .{ cwd, home_tmp.sub_path });
    defer a.free(home);

    var env = EnvMap.init(a);
    defer env.deinit();
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home);

    // No ~/.rawenv exists; uninstall must still succeed and not error out.
    const r = try run(&.{ rawenvBin(), "uninstall", "--force" }, home_tmp.dir, &env);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(contains(r.stdout, "rawenv uninstalled"));

    const rawenv_root = try join(&.{ home, ".rawenv" });
    defer a.free(rawenv_root);
    try testing.expect(!pathExists(rawenv_root));
}
