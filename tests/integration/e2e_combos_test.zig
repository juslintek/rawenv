//! E2E-021 — Service combinations, multi-instance, and port-conflict E2E.
//!
//! These tests exercise rawenv's behaviour when more than one service is
//! involved. They build on the per-stack lifecycle test (E2E-020) and focus on
//! the multi-service surface area:
//!
//!   1. Combination: a project declaring 2-3 distinct real services
//!      (redis + postgres + node) resolves each to its own non-conflicting
//!      port, brings them all up together (started when installed, cleanly
//!      skipped otherwise), and tears them all down so no port is left bound.
//!   2. Multi-instance: two instances of the *same* service
//!      (`[services.redis.cache]` and `[services.redis.session]`) are each
//!      assigned a distinct, non-zero port by the auto-allocator and run
//!      independently through the up/destroy lifecycle.
//!   3. Explicit port override: an explicit `port = N` under a service is
//!      honoured verbatim (it wins over the service's default port).
//!   4. Port conflict: two services pinned to the *same* explicit port are
//!      flagged via `rawenv status --json` (`port_conflict: true`) instead of
//!      silently colliding.
//!
//! Like the lifecycle test, services that are not installed are skipped rather
//! than failing — so the suite is meaningful both in a fully-provisioned dev
//! box and in CI where the datastore binaries are absent. Temp dirs are removed
//! via `tmp.cleanup()`; every explicit port is unique to avoid cross-talk.

const std = @import("std");
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
/// document order. The `services ls --json` / `status --json` shapes emit one
/// such key per service, so this yields the resolved port for each entry
/// without a full JSON parse (and is robust across std.json API churn).
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

/// `rawenv up` reports each service as either started (▶ … started) or
/// "not installed, skipping". True when the service named `name` is referenced
/// either way — i.e. it was considered during activation.
fn serviceConsidered(r: RunResult, name: []const u8) bool {
    return r.outContains(name);
}

/// Whether `rawenv up` actually started at least one service (vs. skipping all).
fn anyStarted(r: RunResult) bool {
    return r.outContains("started");
}

/// Write rawenv.toml into the temp project.
fn writeConfig(tmp: *std.testing.TmpDir, toml: []const u8) !void {
    try tmp.dir.writeFile(io, .{ .sub_path = "rawenv.toml", .data = toml });
}

// ---------------------------------------------------------------------------
// 1. Service combination — multiple distinct services together.
// ---------------------------------------------------------------------------

test "combo: 2-3 services resolve to distinct ports, start together, tear down" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Three distinct services, each pinned to a unique ephemeral-range port so
    // the test is deterministic and never collides with anything real.
    const redis_port: u16 = 47210;
    const pg_port: u16 = 47211;
    const node_port: u16 = 47212;

    var buf: [1024]u8 = undefined;
    const toml = try std.fmt.bufPrint(&buf,
        \\[project]
        \\name = "e2e-combo"
        \\
        \\[services.redis]
        \\version = "7"
        \\port = {d}
        \\
        \\[services.redis.health]
        \\timeout = 5
        \\
        \\[services.postgres]
        \\version = "16"
        \\port = {d}
        \\
        \\[services.postgres.health]
        \\timeout = 5
        \\
        \\[services.node]
        \\version = "22"
        \\port = {d}
        \\
        \\[services.node.health]
        \\timeout = 5
        \\
    , .{ redis_port, pg_port, node_port });
    try writeConfig(&tmp, toml);

    // `services ls --json` must list all three with their explicit, distinct ports.
    {
        const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(r.outContains("redis"));
        try testing.expect(r.outContains("postgres"));
        try testing.expect(r.outContains("node"));

        const ports = try extractPorts(testing.allocator, r.stdout);
        defer testing.allocator.free(ports);
        try testing.expectEqual(@as(usize, 3), ports.len);
        // All three resolved ports are present and mutually distinct.
        try testing.expect(std.mem.indexOfScalar(u16, ports, redis_port) != null);
        try testing.expect(std.mem.indexOfScalar(u16, ports, pg_port) != null);
        try testing.expect(std.mem.indexOfScalar(u16, ports, node_port) != null);
        try testing.expect(ports[0] != ports[1]);
        try testing.expect(ports[1] != ports[2]);
        try testing.expect(ports[0] != ports[2]);
    }

    // Bring all services up in one pass. Each is either started (installed) or
    // skipped (not installed); either way it must be considered by name.
    var started = false;
    {
        const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(serviceConsidered(r, "redis"));
        try testing.expect(serviceConsidered(r, "postgres"));
        try testing.expect(serviceConsidered(r, "node"));
        started = anyStarted(r);
    }

    // Tear everything down. If anything was actually started, destroy the
    // project's services/data so nothing dangles.
    if (started) {
        const d = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp.dir);
        defer d.deinit();
        try testing.expect(d.exitedWith(0));
    }

    // Teardown invariant: every service port is free once the combo is down.
    try testing.expect(portIsFree(redis_port));
    try testing.expect(portIsFree(pg_port));
    try testing.expect(portIsFree(node_port));
}

// ---------------------------------------------------------------------------
// 2. Multi-instance — two instances of the same service.
// ---------------------------------------------------------------------------

test "multi-instance: two redis instances get distinct ports and run independently" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two instances of the same service, NO explicit ports — the auto-allocator
    // must hand each a distinct, non-zero port (default 6379, then next free).
    const toml =
        \\[project]
        \\name = "e2e-multi-instance"
        \\
        \\[services.redis.cache]
        \\version = "7"
        \\
        \\[services.redis.session]
        \\version = "7"
        \\
    ;
    try writeConfig(&tmp, toml);

    var inst_ports: []u16 = &.{};
    {
        const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        // Both instance keys are present and addressable independently.
        try testing.expect(r.outContains("redis.cache"));
        try testing.expect(r.outContains("redis.session"));

        const ports = try extractPorts(testing.allocator, r.stdout);
        // Two instances => two resolved ports, both non-zero and distinct.
        try testing.expectEqual(@as(usize, 2), ports.len);
        try testing.expect(ports[0] != 0);
        try testing.expect(ports[1] != 0);
        try testing.expect(ports[0] != ports[1]);
        inst_ports = ports; // hand off ownership for the teardown check below
    }
    defer testing.allocator.free(inst_ports);

    // Both instances run independently through up; either started or skipped.
    var started = false;
    {
        const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(serviceConsidered(r, "redis.cache"));
        try testing.expect(serviceConsidered(r, "redis.session"));
        started = anyStarted(r);
    }

    if (started) {
        const d = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp.dir);
        defer d.deinit();
        try testing.expect(d.exitedWith(0));
    }

    // Both auto-assigned ports are free once the instances are torn down.
    try testing.expect(portIsFree(inst_ports[0]));
    try testing.expect(portIsFree(inst_ports[1]));
}

// ---------------------------------------------------------------------------
// 3. Explicit port override — the configured port wins over the default.
// ---------------------------------------------------------------------------

test "explicit port override is honored over the service default" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // redis defaults to 6379; pin it to a distinctly non-default port and
    // confirm the override (not the default) is what gets resolved.
    const override_port: u16 = 49231;
    try testing.expect(override_port != 6379);

    var buf: [256]u8 = undefined;
    const toml = try std.fmt.bufPrint(&buf,
        \\[project]
        \\name = "e2e-port-override"
        \\
        \\[services.redis]
        \\version = "7"
        \\port = {d}
        \\
    , .{override_port});
    try writeConfig(&tmp, toml);

    const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));
    try testing.expect(r.outContains("redis"));

    const ports = try extractPorts(testing.allocator, r.stdout);
    defer testing.allocator.free(ports);
    try testing.expectEqual(@as(usize, 1), ports.len);
    // The resolved port is the explicit override, not the redis default.
    try testing.expectEqual(override_port, ports[0]);
    try testing.expect(ports[0] != 6379);
}

// ---------------------------------------------------------------------------
// 4. Port conflict — two services pinned to the same explicit port are flagged.
// ---------------------------------------------------------------------------

test "port conflict between two services is flagged by status --json" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Two redis instances deliberately pinned to the SAME explicit port. This
    // is a misconfiguration rawenv should surface rather than silently accept.
    const clash_port: u16 = 49250;
    var buf: [320]u8 = undefined;
    const toml = try std.fmt.bufPrint(&buf,
        \\[project]
        \\name = "e2e-port-conflict"
        \\
        \\[services.redis.a]
        \\version = "7"
        \\port = {d}
        \\
        \\[services.redis.b]
        \\version = "7"
        \\port = {d}
        \\
    , .{ clash_port, clash_port });
    try writeConfig(&tmp, toml);

    const r = try run(&.{ rawenvBin(), "status", "--json" }, tmp.dir);
    defer r.deinit();
    try testing.expect(r.exitedWith(0));

    // Both instances must report the clashing port and be flagged as conflicting.
    try testing.expect(r.outContains("\"port_conflict\":true"));
    try testing.expect(r.outContains("redis.a"));
    try testing.expect(r.outContains("redis.b"));

    // Both resolved ports are the clash port (explicit override honored even
    // when it produces a conflict — the conflict is reported, not auto-fixed).
    const ports = try extractPorts(testing.allocator, r.stdout);
    defer testing.allocator.free(ports);
    try testing.expectEqual(@as(usize, 2), ports.len);
    try testing.expectEqual(clash_port, ports[0]);
    try testing.expectEqual(clash_port, ports[1]);
}
