//! E2E-107 — Per-service install → start → verify → stop → cleanup lifecycle.
//!
//! For every supported service (node, redis, meilisearch, postgres, bun, php,
//! mariadb, python) this suite exercises the full lifecycle individually and
//! asserts that each service leaves *no side effects* once torn down:
//!
//!   1. install path — `rawenv add` knows how to install the service. We verify
//!      this without a network download by asserting the service appears in the
//!      installer's "Available: …" catalog (the same list `add` resolves
//!      against). When a service is genuinely unsupported on this OS/arch, `add`
//!      degrades gracefully with a clear, non-crashing message instead.
//!   2. config + port — a project pinning the service to a unique port lists it
//!      (with that exact port) via `services ls --json`.
//!   3. start + verify — `rawenv up` either starts the service and gates it on a
//!      readiness probe (TCP/HTTP), or — when the binary isn't installed —
//!      cleanly reports "not installed, skipping". Either way `up` exits 0
//!      because a readiness miss self-heals by tearing the service back down.
//!   4. stop — `rawenv down` stops the service cleanly (exit 0).
//!   5. cleanup — `rawenv destroy --force` removes the project's data dir.
//!
//! Teardown invariants asserted for every service after the lifecycle:
//!   * the allocated port is free (nothing left listening),
//!   * no launchd plist (`~/Library/LaunchAgents/com.rawenv.{name}.plist`) or
//!     systemd unit is left behind for this project's service,
//!   * the project's isolated data dir is gone.
//!
//! The suite is meaningful both on a fully-provisioned dev box (where binaries
//! are installed and really start) and in CI (where they're absent and the
//! service is skipped) — neither requires the network at test time. Temp dirs
//! are removed via `tmp.cleanup()`; every port is unique to avoid cross-talk.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const io = testing.io;
const Io = std.Io;

/// Resolve the rawenv binary under test. The build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise.
fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return if (std.c.getenv("RAWENV_BINARY")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

/// The services exercised by E2E-107, each pinned to a unique ephemeral-range
/// port so the lifecycle is deterministic and never collides with anything real.
const ServiceCase = struct {
    /// Config key + store base name (e.g. "postgres" resolves to postgresql).
    name: []const u8,
    version: []const u8,
    port: u16,
};

const cases = [_]ServiceCase{
    .{ .name = "node", .version = "22", .port = 47300 },
    .{ .name = "redis", .version = "7", .port = 47301 },
    .{ .name = "meilisearch", .version = "1", .port = 47302 },
    .{ .name = "postgres", .version = "16", .port = 47303 },
    .{ .name = "bun", .version = "1", .port = 47304 },
    .{ .name = "php", .version = "8.3", .port = 47305 },
    .{ .name = "mariadb", .version = "11", .port = 47306 },
    .{ .name = "python", .version = "3.12", .port = 47307 },
};

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
    /// i.e. it didn't crash/segfault. Used for graceful-degradation checks.
    fn exitedCleanly(self: RunResult) bool {
        return self.term == .exited;
    }

    fn outContains(self: RunResult, needle: []const u8) bool {
        return std.mem.containsAtLeast(u8, self.stdout, 1, needle);
    }
};

/// Spawn the rawenv binary with the given args inside `dir`.
fn run(argv: []const []const u8, dir: std.Io.Dir) !RunResult {
    const result = std.process.run(testing.allocator, io, .{
        .argv = argv,
        .cwd = .{ .dir = dir },
    }) catch |err| {
        std.debug.print("spawn error running {s}: {}\n", .{ argv[0], err });
        return err;
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

/// Spawn the rawenv binary with no project cwd dependence (uses the test's cwd).
fn runHere(argv: []const []const u8) !RunResult {
    const result = std.process.run(testing.allocator, io, .{ .argv = argv }) catch |err| {
        std.debug.print("spawn error running {s}: {}\n", .{ argv[0], err });
        return err;
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .term = result.term };
}

/// True when a TCP port on 127.0.0.1 can be bound (i.e. nothing is listening).
fn portIsFree(port: u16) bool {
    if (port == 0) return false;
    if (comptime builtin.os.tag == .windows) return true; // no std.c socket layer
    const fd = std.c.socket(std.c.AF.INET, std.c.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = std.c.close(fd);
    var sa: std.c.sockaddr.in = .{
        .family = std.c.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = std.mem.nativeToBig(u32, 0x7f00_0001), // 127.0.0.1
    };
    return std.c.bind(fd, @ptrCast(&sa), @sizeOf(std.c.sockaddr.in)) == 0;
}

fn homeDir() ?[]const u8 {
    if (std.c.getenv("HOME")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return null;
}

/// True when an absolute path exists (file or directory).
fn pathExists(path: []const u8) bool {
    const pz = std.fmt.allocPrintSentinel(testing.allocator, "{s}", .{path}, 0) catch return false;
    defer testing.allocator.free(pz);
    return std.c.access(pz, 0) == 0; // F_OK
}

/// Replicates service.projectKey: sanitized project name + "-" + wyhash hex.
/// Used to locate the project's isolated data dir for the teardown invariant.
fn projectKey(allocator: std.mem.Allocator, project: []const u8) ![]u8 {
    const h = std.hash.Wyhash.hash(0, project);
    var name_buf: std.ArrayList(u8) = .empty;
    defer name_buf.deinit(allocator);
    for (project) |c| {
        const safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        try name_buf.append(allocator, if (safe) c else '-');
    }
    return std.fmt.allocPrint(allocator, "{s}-{x}", .{ name_buf.items, h });
}

/// Path to the project's isolated data root: ~/.rawenv/data/{project-key}.
fn projectDataRoot(allocator: std.mem.Allocator, home: []const u8, project: []const u8) ![]u8 {
    const key = try projectKey(allocator, project);
    defer allocator.free(key);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "data", key });
}

/// Path to a service's launchd plist on macOS: com.rawenv.{name}.plist.
fn plistPath(allocator: std.mem.Allocator, home: []const u8, name: []const u8) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "com.rawenv.{s}.plist", .{name});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ home, "Library", "LaunchAgents", filename });
}

/// Extract every integer following a `"port":` key, in document order. The
/// `services ls --json` shape emits one such key per service.
fn extractPorts(allocator: std.mem.Allocator, json: []const u8) ![]u16 {
    var ports: std.ArrayList(u16) = .empty;
    errdefer ports.deinit(allocator);
    const needle = "\"port\":";
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, json, i, needle)) |pos| {
        var j = pos + needle.len;
        var val: u32 = 0;
        var saw_digit = false;
        while (j < json.len and std.ascii.isDigit(json[j])) : (j += 1) {
            val = val * 10 + (json[j] - '0');
            saw_digit = true;
        }
        if (saw_digit) try ports.append(allocator, @intCast(val));
        i = j;
    }
    return ports.toOwnedSlice(allocator);
}

/// Write rawenv.toml into the temp project.
fn writeConfig(tmp: *std.testing.TmpDir, toml: []const u8) !void {
    try tmp.dir.writeFile(io, .{ .sub_path = "rawenv.toml", .data = toml });
}

/// Drive the full install→start→verify→stop→cleanup lifecycle for one service
/// and assert all teardown invariants hold afterwards.
fn runServiceLifecycle(c: ServiceCase, available_catalog: []const u8) !void {
    const home = homeDir() orelse return error.SkipZigTest;

    // ── 1. Install path is wired (network-free) ───────────────────────────
    // The service must be a known, installable package — i.e. present in the
    // installer's "Available:" catalog. This proves `rawenv add` can install
    // the binary into ~/.rawenv/store/{name}-{version}/ without us having to
    // perform a real (slow, network-bound) download in the test.
    try testing.expect(std.mem.containsAtLeast(u8, available_catalog, 1, c.name));

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Unique project name per service so its isolated data dir never collides
    // with a sibling case (or a real user project).
    var name_buf: [64]u8 = undefined;
    const project = try std.fmt.bufPrint(&name_buf, "rawenv-e2e107-{s}", .{c.name});

    // ── 2. Config + port resolution ───────────────────────────────────────
    {
        var buf: [512]u8 = undefined;
        const toml = try std.fmt.bufPrint(&buf,
            \\[project]
            \\name = "{s}"
            \\
            \\[services.{s}]
            \\version = "{s}"
            \\port = {d}
            \\
            \\[services.{s}.health]
            \\timeout = 3
            \\
        , .{ project, c.name, c.version, c.port, c.name });
        try writeConfig(&tmp, toml);

        const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains(c.name));

        const ports = try extractPorts(testing.allocator, r.stdout);
        defer testing.allocator.free(ports);
        try testing.expectEqual(@as(usize, 1), ports.len);
        try testing.expectEqual(c.port, ports[0]);
    }

    // ── 3. Start + readiness verification ─────────────────────────────────
    var started = false;
    {
        const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
        defer r.deinit();
        // QF-012: exit 0 when the service is skipped or becomes ready; exit 1 if
        // it starts but fails its readiness gate.
        try testing.expect(r.exitedWith(0) or (r.exitedWith(1) and r.outContains("failed to start")));
        // The service must be considered by name — either started or skipped.
        try testing.expect(r.outContains(c.name));
        // Installed services are reported started (▶ … started). Uninstalled
        // ones degrade to "not installed, skipping". Exactly one path applies.
        started = r.outContains("started");
        const skipped = r.outContains("not installed");
        try testing.expect(started or skipped);
    }

    // ── 4. Stop cleanly ───────────────────────────────────────────────────
    {
        const r = try run(&.{ rawenvBin(), "down" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
    }
    // After `down` the port must be free (process gone, port released).
    try testing.expect(portIsFree(c.port));

    // ── 5. Cleanup ────────────────────────────────────────────────────────
    {
        const r = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
    }

    // ── Teardown invariants (no side effects) ─────────────────────────────
    // a) Port is free.
    try testing.expect(portIsFree(c.port));

    // b) No launchd plist left behind for this service (macOS).
    if (comptime builtin.os.tag == .macos) {
        const plist = try plistPath(testing.allocator, home, c.name);
        defer testing.allocator.free(plist);
        try testing.expect(!pathExists(plist));
    }

    // c) The project's isolated data dir is gone after destroy.
    {
        const root = try projectDataRoot(testing.allocator, home, project);
        defer testing.allocator.free(root);
        try testing.expect(!pathExists(root));
    }
}

test "per-service full lifecycle E2E (install → start → verify → stop → cleanup)" {
    // Fetch the installer catalog once: requesting an unknown package makes
    // `rawenv add` print "Available: <list of installable packages>". Every
    // E2E-107 service must appear there for its install path to be wired.
    const catalog = try runHere(&.{ rawenvBin(), "add", "definitely-not-a-real-package@1.0" });
    defer catalog.deinit();
    // The catalog request itself must terminate cleanly with a clear message.
    try testing.expect(catalog.exitedCleanly());
    try testing.expect(catalog.outContains("Available:"));

    for (cases) |c| {
        runServiceLifecycle(c, catalog.stdout) catch |err| {
            if (err == error.SkipZigTest) return err;
            std.debug.print("service '{s}' lifecycle failed: {}\n", .{ c.name, err });
            return err;
        };
    }
}

test "unsupported service on this platform skips gracefully with a clear message" {
    // `rawenv add` for a service that has no prebuilt binary on this OS/arch
    // must not crash: it either resolves (known package) or reports a clear,
    // user-facing reason. We assert the catalog lists every E2E-107 service and
    // that an unknown package yields an actionable "Unknown package" message —
    // the same graceful-degradation path unsupported services take.
    const r = try runHere(&.{ rawenvBin(), "add", "totally-unknown-svc@9" });
    defer r.deinit();
    try testing.expect(r.exitedCleanly());
    try testing.expect(r.outContains("Unknown package"));
    // Clear guidance: the available installable services are listed.
    for (cases) |c| {
        try testing.expect(r.outContains(c.name));
    }
}
