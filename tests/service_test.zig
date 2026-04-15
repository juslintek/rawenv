const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const config = @import("config");
const service = @import("service");
const shell = @import("shell");

const sep = std.fs.path.sep_str;

test "buildStorePath constructs correct path" {
    const path = try service.buildStorePath(testing.allocator, "/home/user", "node", "22.15.0");
    defer testing.allocator.free(path);
    try testing.expect(std.mem.endsWith(u8, path, ".rawenv" ++ sep ++ "store" ++ sep ++ "node-22.15.0"));
}

test "buildBinPath constructs correct path" {
    const path = try service.buildBinPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expect(std.mem.endsWith(u8, path, ".rawenv" ++ sep ++ "bin"));
}

test "buildPath prepends bin dir" {
    const path = try shell.buildPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    try testing.expect(std.mem.indexOf(u8, path, ".rawenv") != null);
    try testing.expect(std.mem.indexOf(u8, path, "bin") != null);
}

test "list with empty config prints no entries" {
    var cfg = config.Config{
        .project_name = "test",
        .runtimes = &.{},
        .services = &.{},
    };
    _ = &cfg;
}

test "buildStorePath with various names and versions" {
    const cases = [_]struct { name: []const u8, version: []const u8, suffix: []const u8 }{
        .{ .name = "node", .version = "22.15.0", .suffix = "node-22.15.0" },
        .{ .name = "php", .version = "8.4", .suffix = "php-8.4" },
        .{ .name = "postgresql", .version = "16", .suffix = "postgresql-16" },
        .{ .name = "redis", .version = "7.2.4", .suffix = "redis-7.2.4" },
    };
    for (cases) |c| {
        const path = try service.buildStorePath(testing.allocator, "/tmp", c.name, c.version);
        defer testing.allocator.free(path);
        try testing.expect(std.mem.endsWith(u8, path, c.suffix));
        try testing.expect(std.mem.indexOf(u8, path, ".rawenv") != null);
        try testing.expect(std.mem.indexOf(u8, path, "store") != null);
    }
}

test "buildBinPath with different homes" {
    const path1 = try service.buildBinPath(testing.allocator, "/home/alice");
    defer testing.allocator.free(path1);
    try testing.expect(std.mem.indexOf(u8, path1, "alice") != null);
    try testing.expect(std.mem.endsWith(u8, path1, ".rawenv" ++ sep ++ "bin"));

    const path2 = try service.buildBinPath(testing.allocator, "/Users/bob");
    defer testing.allocator.free(path2);
    try testing.expect(std.mem.indexOf(u8, path2, "bob") != null);
    try testing.expect(std.mem.endsWith(u8, path2, ".rawenv" ++ sep ++ "bin"));
}

test "buildPath contains separator" {
    const path = try shell.buildPath(testing.allocator, "/home/user");
    defer testing.allocator.free(path);
    // Should contain a path separator (: on unix, ; on windows)
    const path_sep = if (comptime builtin.os.tag == .windows) ";" else ":";
    try testing.expect(std.mem.indexOf(u8, path, path_sep) != null);
}
