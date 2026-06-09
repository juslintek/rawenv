const std = @import("std");
const testing = std.testing;
const io = testing.io;

fn rawenvBin() []const u8 {
    return "/Volumes/Projects/rawenv/zig-out/bin/rawenv";
}

test "rawenv add unknown package returns error" {
    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "add", "nonexistent@1.0" },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Error: unknown package"));
}

test "rawenv add unknown version returns error" {
    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "add", "node@99.99" },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Error: unknown version"));
}
