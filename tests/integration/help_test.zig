const std = @import("std");
const testing = std.testing;
const io = testing.io;

fn rawenvBin() []const u8 {
    return if (std.c.getenv("RAWENV_BIN")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

test "rawenv --help shows usage" {
    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "--help" },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "rawenv"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "init"));
}

test "rawenv --version shows version" {
    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "--version" },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "rawenv") or
        std.mem.containsAtLeast(u8, result.stdout, 1, "0."));
}
