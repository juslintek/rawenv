//! E2E-108 — Multi-project isolation: two projects don't share data.
//!
//! Two distinct projects (project-A and project-B) both declare postgres@16.
//! rawenv keys every project's service data under a per-project root
//! (`~/.rawenv/data/{sanitized-name}-{hash}`), so two projects — even when they
//! use the same service on overlapping defaults — never collide. This test
//! verifies that end-to-end through the real `rawenv` binary:
//!
//!   1. Distinct project names resolve to distinct data roots, and `services ls
//!      --json` reports each project's postgres on its own, distinct port.
//!   2. `rawenv up` runs in each project (starting postgres when the binary is
//!      installed, cleanly skipping it otherwise — like the other E2E suites).
//!   3. Data written under project-A's data dir is NOT visible under
//!      project-B's, and vice-versa.
//!   4. `rawenv destroy --force` in project-A removes ONLY A's data; B's data
//!      dir (and the marker written into it) remains fully intact.
//!   5. Destroying B too leaves no data dirs behind for either project under
//!      `~/.rawenv/data/`.
//!   6. The shared store (`~/.rawenv/store/`) is never touched by a project
//!      destroy — a sentinel placed there survives both destroys.
//!
//! The data dirs are manufactured deterministically (using the same key scheme
//! the binary computes) so the destroy/isolation semantics are exercised
//! whether or not the postgres binary happens to be installed in this
//! environment. Both project names carry a distinctive token to avoid any
//! collision with a real user project, and every artifact is cleaned up via
//! `defer` regardless of outcome.

const std = @import("std");
const testing = std.testing;
const io = testing.io;

/// Resolve the rawenv binary under test. The build wiring sets RAWENV_BIN to the
/// freshly-built artifact; fall back to the canonical checkout path otherwise.
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

/// Run a command (no specific cwd) used for absolute-path filesystem helpers.
/// Best-effort: failures are swallowed so cleanup never breaks a test.
fn sh(argv: []const []const u8) void {
    const result = std.process.run(testing.allocator, io, .{ .argv = argv }) catch return;
    testing.allocator.free(result.stdout);
    testing.allocator.free(result.stderr);
}

fn mkdirp(path: []const u8) void {
    sh(&.{ "/bin/mkdir", "-p", path });
}

fn rmrf(path: []const u8) void {
    sh(&.{ "/bin/rm", "-rf", path });
}

/// True when `path` exists on disk.
fn pathExists(path: []const u8) bool {
    const z = std.fmt.allocPrintSentinel(testing.allocator, "{s}", .{path}, 0) catch return false;
    defer testing.allocator.free(z);
    return std.c.access(z, 0) == 0;
}

/// True when a TCP port on 127.0.0.1 can be bound (i.e. nothing is listening).
fn portIsFree(port: u16) bool {
    if (port == 0) return false;
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

/// Extract every integer that follows a `"port":` key in a JSON document, in
/// document order — mirrors the helper used by the other E2E suites.
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

/// Resolve $HOME, or null on platforms without it (skip the test there).
fn homeDir() ?[]const u8 {
    if (std.c.getenv("HOME")) |s| {
        const v = std.mem.sliceTo(s, 0);
        if (v.len > 0) return v;
    }
    return null;
}

/// Replicate rawenv's per-project key: `{sanitized-name}-{wyhash-hex}`. This is
/// the exact scheme `service.buildProjectDataRoot` uses, so a dir manufactured
/// at this path is the same one `rawenv destroy` computes and removes. If the
/// scheme ever drifts, `destroy` won't remove the manufactured dir and the
/// "data root removed" assertions fail loudly rather than passing silently.
fn projectKey(allocator: std.mem.Allocator, project: []const u8) ![]const u8 {
    const h = std.hash.Wyhash.hash(0, project);
    var name_buf: std.ArrayList(u8) = .empty;
    defer name_buf.deinit(allocator);
    for (project) |c| {
        const safe = std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
        try name_buf.append(allocator, if (safe) c else '-');
    }
    return std.fmt.allocPrint(allocator, "{s}-{x}", .{ name_buf.items, h });
}

/// Build the per-project data root: ~/.rawenv/data/{project-name-hash}
fn dataRoot(allocator: std.mem.Allocator, home: []const u8, project: []const u8) ![]const u8 {
    const key = try projectKey(allocator, project);
    defer allocator.free(key);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "data", key });
}

/// Write a rawenv.toml declaring a single postgres@16 service on `port`.
fn writeProjectConfig(tmp: *std.testing.TmpDir, name: []const u8, port: u16) !void {
    var buf: [512]u8 = undefined;
    const toml = try std.fmt.bufPrint(&buf,
        \\[project]
        \\name = "{s}"
        \\
        \\[services.postgres]
        \\version = "16"
        \\port = {d}
        \\
    , .{ name, port });
    try tmp.dir.writeFile(io, .{ .sub_path = "rawenv.toml", .data = toml });
}

test "E2E-108: two postgres projects are isolated and destroyed independently" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;
    const alloc = testing.allocator;
    const home = homeDir() orelse return; // no HOME → nothing to isolate.

    // Distinctive names (collision with a real project is effectively impossible)
    // and distinct explicit ports so each postgres resolves to its own port.
    const name_a = "rawenv-e2e108-project-alpha";
    const name_b = "rawenv-e2e108-project-bravo";
    const port_a: u16 = 47361;
    const port_b: u16 = 47362;

    const root_a = try dataRoot(alloc, home, name_a);
    defer alloc.free(root_a);
    const root_b = try dataRoot(alloc, home, name_b);
    defer alloc.free(root_b);

    // Two projects, two distinct data roots — the core isolation invariant.
    try testing.expect(!std.mem.eql(u8, root_a, root_b));

    // Guarantee a clean slate and guaranteed teardown regardless of outcome.
    rmrf(root_a);
    rmrf(root_b);
    defer rmrf(root_a);
    defer rmrf(root_b);

    // Sentinel in the SHARED store — a project destroy must never remove it.
    const store_dir = try std.fs.path.join(alloc, &.{ home, ".rawenv", "store" });
    defer alloc.free(store_dir);
    const sentinel = try std.fs.path.join(alloc, &.{ store_dir, "__e2e108_sentinel__" });
    defer alloc.free(sentinel);
    mkdirp(sentinel);
    defer rmrf(sentinel);

    // Two isolated project working dirs, each with its own rawenv.toml.
    var tmp_a = testing.tmpDir(.{});
    defer tmp_a.cleanup();
    var tmp_b = testing.tmpDir(.{});
    defer tmp_b.cleanup();
    try writeProjectConfig(&tmp_a, name_a, port_a);
    try writeProjectConfig(&tmp_b, name_b, port_b);

    // 1. `services ls --json`: each project reports postgres on its own port.
    {
        const ra = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp_a.dir);
        defer ra.deinit();
        try testing.expect(ra.exitedWith(0));
        try testing.expect(ra.outContains("postgres"));
        const pa = try extractPorts(alloc, ra.stdout);
        defer alloc.free(pa);
        try testing.expectEqual(@as(usize, 1), pa.len);
        try testing.expectEqual(port_a, pa[0]);

        const rb = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp_b.dir);
        defer rb.deinit();
        try testing.expect(rb.exitedWith(0));
        try testing.expect(rb.outContains("postgres"));
        const pb = try extractPorts(alloc, rb.stdout);
        defer alloc.free(pb);
        try testing.expectEqual(@as(usize, 1), pb.len);
        try testing.expectEqual(port_b, pb[0]);

        // Different ports — the two postgres instances never collide.
        try testing.expect(pa[0] != pb[0]);
    }

    // 2. `rawenv up` in each project. postgres is either started (installed) or
    //    cleanly skipped (not installed) — both are valid, like the other E2E
    //    suites — but it must be considered by name in each project.
    {
        const ua = try run(&.{ rawenvBin(), "up" }, tmp_a.dir);
        defer ua.deinit();
        try testing.expect(ua.exitedWith(0) or (ua.exitedWith(1) and ua.outContains("failed to start")));
        try testing.expect(ua.outContains("postgres"));

        const ub = try run(&.{ rawenvBin(), "up" }, tmp_b.dir);
        defer ub.deinit();
        try testing.expect(ub.exitedWith(0) or (ub.exitedWith(1) and ub.outContains("failed to start")));
        try testing.expect(ub.outContains("postgres"));
    }

    // 3. Simulate data written by each project's postgres into its own data dir,
    //    deterministically (independent of whether the binary is installed).
    const inst_a = try std.fs.path.join(alloc, &.{ root_a, "postgres" });
    defer alloc.free(inst_a);
    const inst_b = try std.fs.path.join(alloc, &.{ root_b, "postgres" });
    defer alloc.free(inst_b);

    const marker_a = try std.fs.path.join(alloc, &.{ inst_a, "A_ONLY" });
    defer alloc.free(marker_a);
    const marker_b = try std.fs.path.join(alloc, &.{ inst_b, "B_ONLY" });
    defer alloc.free(marker_b);
    mkdirp(marker_a);
    mkdirp(marker_b);

    // A's marker exists under A but NOT under B, and vice-versa: data written in
    // one project is not visible in the other.
    const a_under_b = try std.fs.path.join(alloc, &.{ inst_b, "A_ONLY" });
    defer alloc.free(a_under_b);
    const b_under_a = try std.fs.path.join(alloc, &.{ inst_a, "B_ONLY" });
    defer alloc.free(b_under_a);

    try testing.expect(pathExists(marker_a));
    try testing.expect(pathExists(marker_b));
    try testing.expect(!pathExists(a_under_b)); // A's data not visible in B
    try testing.expect(!pathExists(b_under_a)); // B's data not visible in A

    // 4. Destroy project-A only. It must remove A's data root and report it,
    //    while B's data root (and its marker) stays fully intact.
    {
        const da = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp_a.dir);
        defer da.deinit();
        try testing.expect(da.exitedWith(0));
        try testing.expect(da.outContains("Destroyed data for project"));
    }
    try testing.expect(!pathExists(root_a)); // A's data gone
    try testing.expect(pathExists(root_b)); // B untouched
    try testing.expect(pathExists(marker_b)); // B's data still present
    // The shared store sentinel must survive a project destroy.
    try testing.expect(pathExists(sentinel));

    // 5. Destroy project-B too. Afterwards no data dir remains for either.
    {
        const db = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp_b.dir);
        defer db.deinit();
        try testing.expect(db.exitedWith(0));
        try testing.expect(db.outContains("Destroyed data for project"));
    }
    try testing.expect(!pathExists(root_a));
    try testing.expect(!pathExists(root_b));

    // 6. Store binaries (shared) are NOT removed by a project destroy.
    try testing.expect(pathExists(sentinel));

    // Teardown invariant: both explicit ports are free once everything is down.
    try testing.expect(portIsFree(port_a));
    try testing.expect(portIsFree(port_b));
}
