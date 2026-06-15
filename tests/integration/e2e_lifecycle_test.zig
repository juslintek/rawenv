//! E2E-020 — Per-stack full lifecycle end-to-end test.
//!
//! A single data-driven test exercises the complete rawenv lifecycle for every
//! supported stack (node, php, python, rust, go, ruby). For each stack it:
//!   1. Creates an isolated temp project with the stack's marker file.
//!   2. Detects the stack via the CLI (`rawenv detect --json`) and asserts the
//!      runtime is reported (and that detection is non-mutating).
//!   3. Generates config via the CLI (`rawenv init`) and asserts the runtime is
//!      written into rawenv.toml.
//!   4. Writes a config with a service bound to a per-case unique port and
//!      confirms config generation round-trips that port (`services ls --json`).
//!   5. Runs the lifecycle (`rawenv up`): services that are installed are
//!      started, gated on readiness (verified responding), and torn down;
//!      services that are not installed are cleanly skipped. The per-case port
//!      is asserted free after the lifecycle so nothing is left dangling.
//!
//! Temp dirs are removed via `tmp.cleanup()`. Ports are unique per case.

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
    return "zig-out/bin/rawenv";
}

const StackCase = struct {
    /// Expected runtime key reported by `detect` / written by `init`.
    stack: []const u8,
    /// Marker file that triggers detection of this stack.
    marker_file: []const u8,
    marker_content: []const u8,
    /// Service exercised during the lifecycle step.
    service: []const u8,
    service_version: []const u8,
};

const cases = [_]StackCase{
    .{ .stack = "node", .marker_file = "package.json", .marker_content = "{\"engines\":{\"node\":\">=22\"}}", .service = "redis", .service_version = "7" },
    .{ .stack = "php", .marker_file = "composer.json", .marker_content = "{\"require\":{\"php\":\"^8.3\"}}", .service = "redis", .service_version = "7" },
    .{ .stack = "python", .marker_file = "requirements.txt", .marker_content = "flask==3.0\nrequests>=2.31\n", .service = "redis", .service_version = "7" },
    .{ .stack = "rust", .marker_file = "Cargo.toml", .marker_content = "[package]\nname = \"myapp\"\nversion = \"0.1.0\"\n", .service = "redis", .service_version = "7" },
    .{ .stack = "go", .marker_file = "go.mod", .marker_content = "module example.com/myapp\n\ngo 1.22\n", .service = "redis", .service_version = "7" },
    .{ .stack = "ruby", .marker_file = "Gemfile", .marker_content = "source \"https://rubygems.org\"\ngem \"sinatra\"\n", .service = "redis", .service_version = "7" },
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

fn fileExists(dir: std.Io.Dir, name: []const u8) bool {
    const data = dir.readFileAlloc(io, name, testing.allocator, Io.Limit.limited(8192)) catch return false;
    testing.allocator.free(data);
    return true;
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

/// Shared per-stack lifecycle assertions, run for each data-driven case.
fn runStackLifecycle(c: StackCase, port: u16) !void {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // 1. Create the temp project with the stack's marker file.
    try tmp.dir.writeFile(io, .{ .sub_path = c.marker_file, .data = c.marker_content });

    // 2. Detect via CLI — verifies detection correctness and non-mutation.
    {
        const r = try run(&.{ rawenvBin(), "detect", "--json" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));
        try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, "\"runtimes\""));
        try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, c.stack));
        // detect must never write rawenv.toml.
        try testing.expect(!fileExists(tmp.dir, "rawenv.toml"));
    }

    // 3. Generate config via CLI — verifies `init` writes the detected runtime.
    {
        const r = try run(&.{ rawenvBin(), "init" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));

        const toml = tmp.dir.readFileAlloc(io, "rawenv.toml", testing.allocator, Io.Limit.limited(8192)) catch |err| {
            std.debug.print("[{s}] init produced no rawenv.toml: {} stderr={s}\n", .{ c.stack, err, r.stderr });
            return err;
        };
        defer testing.allocator.free(toml);
        try testing.expect(std.mem.containsAtLeast(u8, toml, 1, "[project]"));
        try testing.expect(std.mem.containsAtLeast(u8, toml, 1, c.stack));
    }

    // 4. Config generation with a per-case unique port; confirm it round-trips.
    {
        var buf: [512]u8 = undefined;
        const toml = try std.fmt.bufPrint(
            &buf,
            "[project]\nname = \"e2e-{s}\"\n\n[runtimes]\n{s} = \"latest\"\n\n[services.{s}]\nversion = \"{s}\"\nport = {d}\n\n[detect]\nauto = true\n",
            .{ c.stack, c.stack, c.service, c.service_version, port },
        );
        try tmp.dir.writeFile(io, .{ .sub_path = "rawenv.toml", .data = toml });

        const r = try run(&.{ rawenvBin(), "services", "ls", "--json" }, tmp.dir);
        defer r.deinit();
        try testing.expect(r.exitedWith(0));

        var pbuf: [8]u8 = undefined;
        const port_str = try std.fmt.bufPrint(&pbuf, "{d}", .{port});
        try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, c.service));
        try testing.expect(std.mem.containsAtLeast(u8, r.stdout, 1, port_str));
    }

    // 5. Lifecycle: start + verify + stop installed services; skip the rest.
    {
        const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
        defer r.deinit();

        // `up` either starts an installed service (which then gets readiness-gated
        // and torn down on failure) or reports it as not installed and skips.
        const started = std.mem.containsAtLeast(u8, r.stdout, 1, "started");
        const skipped = std.mem.containsAtLeast(u8, r.stdout, 1, "not installed");
        try testing.expect(started or skipped);

        // QF-012: exit 0 when every service is skipped or becomes ready; exit 1
        // when an installed service starts but fails its readiness gate.
        const failed = std.mem.containsAtLeast(u8, r.stdout, 1, "failed to start");
        try testing.expect(r.exitedWith(0) or (r.exitedWith(1) and failed));

        // If a real service was started, tear it down via destroy so nothing dangles.
        if (started) {
            const d = try run(&.{ rawenvBin(), "destroy", "--force" }, tmp.dir);
            defer d.deinit();
            try testing.expect(d.exitedWith(0));
        }

        // Teardown invariant: the unique port is free once the lifecycle completes.
        try testing.expect(portIsFree(port));
    }
}

test "per-stack full lifecycle E2E (node, php, python, rust, go, ruby)" {
    // Unique, non-overlapping port per case (ephemeral high range).
    const base_port: u16 = 47100;
    for (cases, 0..) |c, idx| {
        const port: u16 = base_port + @as(u16, @intCast(idx));
        runStackLifecycle(c, port) catch |err| {
            std.debug.print("stack '{s}' lifecycle failed: {}\n", .{ c.stack, err });
            return err;
        };
    }
}
