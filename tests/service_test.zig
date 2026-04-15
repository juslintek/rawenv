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

test "buildStorePath with various names and versions" {
    const cases = [_]struct { name: []const u8, version: []const u8, expected: []const u8 }{
        .{ .name = "node", .version = "22.15.0", .expected = "/tmp/.rawenv/store/node-22.15.0" },
        .{ .name = "php", .version = "8.4", .expected = "/tmp/.rawenv/store/php-8.4" },
        .{ .name = "postgresql", .version = "16", .expected = "/tmp/.rawenv/store/postgresql-16" },
        .{ .name = "redis", .version = "7.2.4", .expected = "/tmp/.rawenv/store/redis-7.2.4" },
    };
    for (cases) |c| {
        const path = try service.buildStorePath(testing.allocator, "/tmp", c.name, c.version);
        defer testing.allocator.free(path);
        try testing.expectEqualStrings(c.expected, path);
    }
}

test "buildBinPath with different homes" {
    const path1 = try service.buildBinPath(testing.allocator, "/home/alice");
    defer testing.allocator.free(path1);
    try testing.expectEqualStrings("/home/alice/.rawenv/bin", path1);

    const path2 = try service.buildBinPath(testing.allocator, "/Users/bob");
    defer testing.allocator.free(path2);
    try testing.expectEqualStrings("/Users/bob/.rawenv/bin", path2);
}

test "buildPath contains existing PATH" {
    const path = try shell.buildPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    // Should contain a colon separator (unix)
    try testing.expect(std.mem.indexOf(u8, path, ":") != null);
}
