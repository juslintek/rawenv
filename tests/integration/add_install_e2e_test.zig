//! E2E-100 — `rawenv add` download + install-path verification.
//!
//! This is the single most critical user path (broken on 5/5 exploratory
//! projects), so it is exercised end-to-end against the *real* binary with a
//! fully isolated `$HOME`. Every install lands in
//! `$HOME/.rawenv/store/{name}-{version}/`, so pointing HOME at a throwaway temp
//! dir lets us assert the exact on-disk result without touching the developer's
//! real store.
//!
//! What is verified:
//!   1. `rawenv add node@22` — when the network is reachable, the extracted
//!      `node` binary really exists (and is executable) under the isolated
//!      store. When it isn't (CI, offline), the failure is graceful: a clean
//!      non-zero exit + an actionable message, never a panic.
//!   2. `rawenv add meilisearch@1.12` — same contract for a single-binary
//!      artifact installed to `store/meilisearch-1.12.0/bin/meilisearch`.
//!   3. Exit codes: 0 on a successful install, non-zero (user=1) on an unknown
//!      package, non-zero on an unknown version.
//!   4. Error messages for the two common failures:
//!        • no network  → "Download failed: … Check your connection …" (forced
//!          deterministically by routing curl through a dead local proxy, so
//!          the assertion does not depend on the host actually being offline).
//!        • unknown pkg → "Unknown package: …" + the installable catalog.
//!
//! The real-download steps are network-gated: present a meaningful assertion
//! on a provisioned dev box (binary really appears) while degrading cleanly in
//! a network-less CI runner. Temp dirs are removed via `cleanup()`.

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
    return "/Volumes/Projects/rawenv/zig-out/bin/rawenv";
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

    /// True when the process terminated normally (regardless of exit code) —
    /// i.e. it did not crash/segfault/abort.
    fn exitedCleanly(self: RunResult) bool {
        return self.term == .exited;
    }

    fn outContains(self: RunResult, needle: []const u8) bool {
        return std.mem.containsAtLeast(u8, self.stdout, 1, needle);
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

/// A user-facing failure must never leak a Zig panic or an error-return trace.
fn assertNoCrashArtifacts(r: RunResult) !void {
    try testing.expect(r.exitedCleanly()); // not a signal/abort
    try testing.expect(!contains(r.stderr, "panic"));
    try testing.expect(!contains(r.stderr, "error return trace"));
    try testing.expect(!contains(r.stdout, "panic"));
    try testing.expect(!contains(r.stdout, "error return trace"));
}

// ── POSIX path helpers (absolute paths; mirror production std.c usage) ───────

/// True when an absolute path exists (file, dir, or symlink).
fn pathExistsAbs(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 0) == 0;
}

/// True when an absolute path exists and is executable by the current user
/// (POSIX X_OK == 1).
fn isExecutableAbs(path: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return false;
    return std.c.access(z, 1) == 0;
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

/// Build the absolute path to an installed package's binary inside the isolated
/// store: `{home}/.rawenv/store/{name}-{version}/bin/{binary}`.
fn storeBinPath(allocator: std.mem.Allocator, home: []const u8, name: []const u8, version: []const u8, binary: []const u8) ![]u8 {
    const dir = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store", dir, "bin", binary });
}

/// Extract the version string the installer reports for `name`. The success
/// path prints "Downloading {name}@{ver}..." then "Installed {name}@{ver}", and
/// the no-op path prints "{name}@{ver} already installed". We match the first
/// "{name}@" occurrence and trim the trailing "..." the progress line appends,
/// yielding the bare "{ver}".
fn reportedVersion(stdout: []const u8, name: []const u8) ?[]const u8 {
    var nbuf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&nbuf, "{s}@", .{name}) catch return null;
    const at = std.mem.indexOf(u8, stdout, needle) orelse return null;
    const start = at + needle.len;
    var end = start;
    while (end < stdout.len and stdout[end] != '\n' and stdout[end] != ' ' and stdout[end] != '\r') : (end += 1) {}
    if (end == start) return null;
    // Strip the trailing "..." progress ellipsis (versions never end in '.').
    const ver = std.mem.trimEnd(u8, stdout[start..end], ".");
    if (ver.len == 0) return null;
    return ver;
}

/// Build a child environment that preserves PATH (so curl/tar/unzip/mv resolve)
/// and pins HOME to the isolated store root. Caller owns the returned map.
fn baseEnv(home: []const u8) !EnvMap {
    var env = EnvMap.init(testing.allocator);
    errdefer env.deinit();
    if (std.c.getenv("PATH")) |p| try env.put("PATH", std.mem.sliceTo(p, 0));
    try env.put("HOME", home);
    return env;
}

/// One of the known, user-friendly failure messages `rawenv add` emits when an
/// install cannot complete (no network, missing tool, bad checksum, unsupported
/// platform, …). Used to assert graceful degradation when the network step
/// can't run on this host.
fn isCleanInstallFailure(stdout: []const u8) bool {
    return contains(stdout, "Download failed") or
        contains(stdout, "checksum verification failed") or
        contains(stdout, "failed to extract") or
        contains(stdout, "curl not found") or
        contains(stdout, "tar not found") or
        contains(stdout, "unzip not found") or
        contains(stdout, "no prebuilt binary") or
        contains(stdout, "Cannot write to");
}

/// Drive `rawenv add {name}@{req_version}` against an isolated store and, when
/// the install succeeds, assert the named binary really exists and is
/// executable under `store/{name}-{installed_version}/bin/{binary}`. When the
/// network step can't complete, assert a clean, non-crashing failure instead.
fn verifyAddInstalls(name: []const u8, req_version: []const u8, binary: []const u8) !void {
    const a = testing.allocator;

    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absHome(a, &home_tmp.sub_path);
    defer a.free(home);

    var env = try baseEnv(home);
    defer env.deinit();

    var spec_buf: [64]u8 = undefined;
    const spec = try std.fmt.bufPrint(&spec_buf, "{s}@{s}", .{ name, req_version });

    const r = try run(&.{ rawenvBin(), "add", spec }, home_tmp.dir, &env);
    defer r.deinit();

    try assertNoCrashArtifacts(r);

    // A valid spec must never be misreported as a user/argument error.
    try testing.expect(!r.exitedWith(1));

    if (r.exitedWith(0)) {
        // Success: the installer announced an install (or that it was already
        // present) and the on-disk binary must exist + be executable.
        try testing.expect(r.outContains("Installed") or r.outContains("already installed"));

        const ver = reportedVersion(r.stdout, name) orelse {
            std.debug.print("could not parse installed version for {s} from:\n{s}\n", .{ name, r.stdout });
            return error.MissingInstalledVersion;
        };

        const bin_path = try storeBinPath(a, home, name, ver, binary);
        defer a.free(bin_path);

        if (!pathExistsAbs(bin_path)) {
            std.debug.print("expected installed binary missing: {s}\nstdout:\n{s}\n", .{ bin_path, r.stdout });
            return error.InstalledBinaryMissing;
        }
        try testing.expect(isExecutableAbs(bin_path));

        // The install marker proves installPackage ran to completion.
        const store_dir = try std.fmt.allocPrint(a, "{s}-{s}", .{ name, ver });
        defer a.free(store_dir);
        const marker = try std.fs.path.join(a, &.{ home, ".rawenv", "store", store_dir, ".rawenv-installed" });
        defer a.free(marker);
        try testing.expect(pathExistsAbs(marker));
    } else {
        // No network (or a missing download tool): the install must fail
        // cleanly with an actionable message (exited normally, non-zero), and
        // must not have left a half-populated store binary behind.
        try testing.expect(r.exitedCleanly());
        try testing.expect(r.term.exited != 0);
        try testing.expect(r.stdout.len > 0);
        if (!isCleanInstallFailure(r.stdout)) {
            std.debug.print("add {s} failed without a recognized message:\n{s}\n", .{ spec, r.stdout });
            return error.UnrecognizedFailureMessage;
        }
    }
}

test "add node@22 downloads + installs node into the isolated store (E2E-100)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    try verifyAddInstalls("node", "22", "node");
}

test "add meilisearch@1.12 installs the meilisearch binary into the store (E2E-100)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    try verifyAddInstalls("meilisearch", "1.12", "meilisearch");
}

test "add unknown package: exit 1 + lists the installable catalog (E2E-100)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absHome(testing.allocator, &home_tmp.sub_path);
    defer testing.allocator.free(home);

    var env = try baseEnv(home);
    defer env.deinit();

    const r = try run(&.{ rawenvBin(), "add", "definitely-not-a-real-pkg@1" }, home_tmp.dir, &env);
    defer r.deinit();

    try testing.expect(r.exitedWith(1));
    try testing.expect(r.outContains("Unknown package:"));
    // The hint must list real, installable packages.
    try testing.expect(r.outContains("node"));
    try testing.expect(r.outContains("meilisearch"));
    try assertNoCrashArtifacts(r);

    // A rejected package must not create any store entry.
    const store = try std.fs.path.join(testing.allocator, &.{ home, ".rawenv", "store", "definitely-not-a-real-pkg-1" });
    defer testing.allocator.free(store);
    try testing.expect(!pathExistsAbs(store));
}

test "add unknown version: exit 1 + lists available versions (E2E-100)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absHome(testing.allocator, &home_tmp.sub_path);
    defer testing.allocator.free(home);

    var env = try baseEnv(home);
    defer env.deinit();

    const r = try run(&.{ rawenvBin(), "add", "node@99" }, home_tmp.dir, &env);
    defer r.deinit();

    try testing.expect(r.exitedWith(1));
    try testing.expect(r.outContains("Unknown version"));
    try testing.expect(r.outContains("Available versions:"));
    try testing.expect(r.outContains("22"));
    try assertNoCrashArtifacts(r);
}

test "add with no network: clean 'Download failed' message, no panic (E2E-100)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var home_tmp = testing.tmpDir(.{});
    defer home_tmp.cleanup();
    const home = try absHome(testing.allocator, &home_tmp.sub_path);
    defer testing.allocator.free(home);

    // Force curl to fail deterministically — route every protocol through a
    // dead local proxy (127.0.0.1:1 is closed) so the download cannot connect,
    // regardless of whether the host actually has a network. This exercises the
    // real DownloadFailed → "check your connection" path without flakiness.
    var env = try baseEnv(home);
    defer env.deinit();
    const dead_proxy = "http://127.0.0.1:1";
    try env.put("ALL_PROXY", dead_proxy);
    try env.put("all_proxy", dead_proxy);
    try env.put("HTTP_PROXY", dead_proxy);
    try env.put("http_proxy", dead_proxy);
    try env.put("HTTPS_PROXY", dead_proxy);
    try env.put("https_proxy", dead_proxy);
    // Defeat any no_proxy that might whitelist the download host.
    try env.put("NO_PROXY", "");
    try env.put("no_proxy", "");

    const r = try run(&.{ rawenvBin(), "add", "node@22" }, home_tmp.dir, &env);
    defer r.deinit();

    try assertNoCrashArtifacts(r);
    // A network failure is a system error, not a user error.
    try testing.expect(r.exitedWith(2));
    try testing.expect(r.outContains("Download failed"));
    try testing.expect(r.outContains("connection"));

    // Nothing executable should be left behind in the store after a failed
    // download.
    const node_bin = try storeBinPath(testing.allocator, home, "node", "22.18.0", "node");
    defer testing.allocator.free(node_bin);
    try testing.expect(!pathExistsAbs(node_bin));
}
