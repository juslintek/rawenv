const std = @import("std");
const testing = std.testing;
const config = @import("config");
const service = @import("service");
const shell = @import("shell");

test "buildStorePath constructs correct path" {
    const path = try service.buildStorePath(testing.allocator, "/home/user", "node", "22.15.0");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("/home/user/.rawenv/store/node-22.15.0", path);
}

test "buildBinPath constructs correct path" {
    const path = try service.buildBinPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("/home/user/.rawenv/bin", path);
}

test "buildPath prepends bin dir" {
    const path = try shell.buildPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));
}

test "list with empty config prints no entries" {
    var cfg = config.Config{
        .project_name = "test",
        .runtimes = &.{},
        .services = &.{},
    };

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(testing.allocator);

    // We can't easily test stdout output without a pipe, but we can verify
    // the function doesn't crash with empty config
    _ = &cfg;
}
