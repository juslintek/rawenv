const std = @import("std");
const testing = std.testing;
const io = testing.io;

fn rawenvBin() []const u8 {
    return if (std.c.getenv("RAWENV_BINARY")) |s| std.mem.sliceTo(s, 0) else "zig-out/bin/rawenv";
}

test "rawenv services ls shows header or empty" {
    const result = std.process.run(testing.allocator, io, .{
        .argv = &.{ rawenvBin(), "services", "ls" },
    }) catch |err| {
        std.debug.print("spawn error: {}\n", .{err});
        return err;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    // Should show NAME/VERSION/STATUS header or error about missing rawenv.toml
    const has_header = std.mem.containsAtLeast(u8, result.stdout, 1, "NAME");
    const is_empty = result.stdout.len == 0;
    const has_error = std.mem.containsAtLeast(u8, result.stdout, 1, "rawenv.toml") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "rawenv.toml");
    try testing.expect(has_header or is_empty or has_error);
}
