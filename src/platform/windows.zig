const std = @import("std");
const builtin = @import("builtin");

fn getLocalAppData(allocator: std.mem.Allocator) ![]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(allocator, "LOCALAPPDATA");
    }
    // Fallback for cross-compilation testing on non-Windows
    return error.HomeNotSet;
}

pub fn getDataDir(allocator: std.mem.Allocator) ![]const u8 {
    const base = try getLocalAppData(allocator);
    defer allocator.free(base);
    return std.fs.path.join(allocator, &.{ base, "rawenv" });
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const base = try getLocalAppData(allocator);
    defer allocator.free(base);
    return std.fs.path.join(allocator, &.{ base, "rawenv", "cache" });
}

pub fn getLogDir(allocator: std.mem.Allocator) ![]const u8 {
    const base = try getLocalAppData(allocator);
    defer allocator.free(base);
    return std.fs.path.join(allocator, &.{ base, "rawenv", "logs" });
}

pub fn openUrl(allocator: std.mem.Allocator, url: []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, 3);
    result[0] = try allocator.dupe(u8, "cmd");
    result[1] = try allocator.dupe(u8, "/c start");
    result[2] = try allocator.dupe(u8, url);
    return result;
}

test "openUrl" {
    const args = try openUrl(std.testing.allocator, "https://example.com");
    defer {
        for (args) |a| std.testing.allocator.free(a);
        std.testing.allocator.free(args);
    }
    try std.testing.expectEqual(@as(usize, 3), args.len);
    try std.testing.expectEqualStrings("cmd", args[0]);
    try std.testing.expectEqualStrings("/c start", args[1]);
    try std.testing.expectEqualStrings("https://example.com", args[2]);
}

test "getDataDir returns error on non-windows" {
    if (comptime builtin.os.tag != .windows) {
        try std.testing.expectError(error.HomeNotSet, getDataDir(std.testing.allocator));
    }
}

test "getCacheDir returns error on non-windows" {
    if (comptime builtin.os.tag != .windows) {
        try std.testing.expectError(error.HomeNotSet, getCacheDir(std.testing.allocator));
    }
}

test "getLogDir returns error on non-windows" {
    if (comptime builtin.os.tag != .windows) {
        try std.testing.expectError(error.HomeNotSet, getLogDir(std.testing.allocator));
    }
}
