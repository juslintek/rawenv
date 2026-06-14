// E2E error handling and edge cases (E2E-105).
//
// Spawns the built `rawenv` binary and exercises every user-facing error path:
//   * unknown package        → exit 1 + lists available packages
//   * unknown version        → exit 1 + lists available versions
//   * invalid package spec   → exit 1 + usage hint
//   * `up` with no config    → exit 1 + "No rawenv.toml found"
//   * `status` with no config → exit 0 + graceful hint
//   * corrupt config         → exit 1 + clean parse-error message
//
// Every assertion also verifies the output is user-friendly: no Zig panics,
// no error-return stack traces leak to the user.

const std = @import("std");
const testing = std.testing;
const io = testing.io;

fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return if (std.c.getenv("RAWENV_BINARY")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

const RunResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,

    fn deinit(self: RunResult) void {
        testing.allocator.free(self.stdout);
        testing.allocator.free(self.stderr);
    }
};

/// Run `rawenv <args...>` in `cwd` (or the process cwd when null) and capture
/// stdout/stderr + the exit code. `.exit_code` is 0xFF when the process did not
/// exit normally (signal/abort) — which itself signals a panic/crash.
fn run(argv: []const []const u8, cwd: ?std.Io.Dir) !RunResult {
    const result = std.process.run(testing.allocator, io, .{
        .argv = argv,
        .cwd = if (cwd) |d| .{ .dir = d } else .inherit,
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    const code: u8 = switch (result.term) {
        .exited => |c| @intCast(c),
        else => 0xFF,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .exit_code = code };
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.containsAtLeast(u8, haystack, 1, needle);
}

/// A user-facing error must never leak a Zig panic or an error-return trace.
fn assertNoCrashArtifacts(r: RunResult) !void {
    try testing.expect(!contains(r.stderr, "panic"));
    try testing.expect(!contains(r.stderr, "error return trace"));
    try testing.expect(!contains(r.stdout, "panic"));
    try testing.expect(!contains(r.stdout, "error return trace"));
    // A normal exit (not a signal/abort) — 0xFF means the process crashed.
    try testing.expect(r.exit_code != 0xFF);
}

test "add unknown package: exit 1 + lists available packages" {
    const r = try run(&.{ rawenvBin(), "add", "nonexistent@1" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "Unknown package:"));
    // The hint must list real, installable package names.
    try testing.expect(contains(r.stdout, "node"));
    try testing.expect(contains(r.stdout, "postgres"));
    try testing.expect(contains(r.stdout, "redis"));
    try assertNoCrashArtifacts(r);
}

test "add unknown version: exit 1 + lists available versions" {
    const r = try run(&.{ rawenvBin(), "add", "node@99" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "Unknown version"));
    try testing.expect(contains(r.stdout, "Available versions:"));
    // node's only supported major is 22.
    try testing.expect(contains(r.stdout, "22"));
    try assertNoCrashArtifacts(r);
}

test "add unknown version for postgres lists all supported majors" {
    const r = try run(&.{ rawenvBin(), "add", "postgres@99" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "Unknown version"));
    try testing.expect(contains(r.stdout, "16"));
    try testing.expect(contains(r.stdout, "17"));
    try testing.expect(contains(r.stdout, "18"));
    try assertNoCrashArtifacts(r);
}

test "add invalid spec (no @version): exit 1 + usage hint" {
    const r = try run(&.{ rawenvBin(), "add", "node" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "invalid package spec"));
    try testing.expect(contains(r.stdout, "<package>@<version>"));
    try assertNoCrashArtifacts(r);
}

test "add with no package argument: exit 1 + usage hint" {
    const r = try run(&.{ rawenvBin(), "add" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "missing package"));
    try assertNoCrashArtifacts(r);
}

test "up with no rawenv.toml: exit 1 + 'No rawenv.toml found'" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "No rawenv.toml found"));
    try assertNoCrashArtifacts(r);
}

test "down with no rawenv.toml: exit 1 + 'No rawenv.toml found'" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "down" }, tmp.dir);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "No rawenv.toml found"));
    try assertNoCrashArtifacts(r);
}

test "status with no config: graceful message, exit 0" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "status" }, tmp.dir);
    defer r.deinit();

    // status is non-fatal without a config — it hints at `rawenv init`.
    try testing.expectEqual(@as(u8, 0), r.exit_code);
    try testing.expect(contains(r.stdout, "No rawenv.toml found"));
    try assertNoCrashArtifacts(r);
}

test "corrupt config: status reports invalid config, no panic" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Unterminated section header — fails config.parse with InvalidToml.
    tmp.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data = "[services\nthis is not = valid",
    }) catch @panic("failed to write rawenv.toml");

    const r = try run(&.{ rawenvBin(), "status" }, tmp.dir);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "invalid"));
    try assertNoCrashArtifacts(r);
}

test "corrupt config: up reports parse failure, no panic" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data = "[unclosed-section",
    }) catch @panic("failed to write rawenv.toml");

    const r = try run(&.{ rawenvBin(), "up" }, tmp.dir);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "parse rawenv.toml"));
    try assertNoCrashArtifacts(r);
}

test "corrupt config: status --json stays structured" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data = "[broken",
    }) catch @panic("failed to write rawenv.toml");

    const r = try run(&.{ rawenvBin(), "status", "--json" }, tmp.dir);
    defer r.deinit();

    try testing.expect(contains(r.stdout, "\"config_valid\":false"));
    try assertNoCrashArtifacts(r);
}

test "unknown command: exit 1 + help hint, no panic" {
    const r = try run(&.{ rawenvBin(), "bogus-command" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "unknown command"));
    try testing.expect(contains(r.stdout, "--help"));
    try assertNoCrashArtifacts(r);
}

test "tunnel with invalid port: exit 1 + clear message" {
    const r = try run(&.{ rawenvBin(), "tunnel", "not-a-number" }, null);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "invalid port"));
    try assertNoCrashArtifacts(r);
}

test "import missing file: exit 1 + clear message" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const r = try run(&.{ rawenvBin(), "import", "does-not-exist.yml" }, tmp.dir);
    defer r.deinit();

    try testing.expectEqual(@as(u8, 1), r.exit_code);
    try testing.expect(contains(r.stdout, "could not read"));
    try assertNoCrashArtifacts(r);
}
