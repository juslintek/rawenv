const std = @import("std");
const testing = std.testing;
const io = testing.io;

fn rawenvBin() []const u8 {
    if (std.c.getenv("RAWENV_BIN")) |p| {
        const s = std.mem.sliceTo(p, 0);
        if (s.len > 0) return s;
    }
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

test "rawenv status without rawenv.toml hints at init" {
    // Empty temp dir: no rawenv.toml present.
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "status" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "No rawenv.toml found"));
}

test "rawenv status --json without rawenv.toml returns structured output" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "status", "--json" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"config_found\":false"));
}

test "rawenv status reports project and services" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data =
        \\name = "demo-app"
        \\
        \\[services.redis]
        \\version = "7"
        ,
    }) catch @panic("failed to write rawenv.toml");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "status" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "demo-app"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "redis"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Config:"));
}

test "rawenv status --json reports valid config" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(io, .{
        .sub_path = "rawenv.toml",
        .data =
        \\name = "demo-app"
        \\
        \\[services.redis]
        \\version = "7"
        ,
    }) catch @panic("failed to write rawenv.toml");

    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "status", "--json" },
        .cwd = .{ .dir = tmp.dir },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"config_valid\":true"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"project\":\"demo-app\""));
}
