const std = @import("std");
const builtin = @import("builtin");

fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv("HOME");
}

pub fn getDataDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "rawenv" });
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Caches", "rawenv" });
}

pub fn getLogDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, "Library", "Logs", "rawenv" });
}

pub fn launchdLabel(allocator: std.mem.Allocator, service_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "com.rawenv.{s}", .{service_name});
}

pub fn launchdPlist(allocator: std.mem.Allocator, service_name: []const u8, binary_path: []const u8, args: []const []const u8, data_dir: []const u8) ![]const u8 {
    const label = try launchdLabel(allocator, service_name);
    defer allocator.free(label);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key>
        \\  <string>
    );
    try w.writeAll(label);
    try w.writeAll(
        \\</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\    <string>
    );
    try w.writeAll(binary_path);
    try w.writeAll("</string>\n");
    for (args) |arg| {
        try w.writeAll("    <string>");
        try w.writeAll(arg);
        try w.writeAll("</string>\n");
    }
    try w.writeAll(
        \\  </array>
        \\  <key>WorkingDirectory</key>
        \\  <string>
    );
    try w.writeAll(data_dir);
    try w.writeAll(
        \\</string>
        \\  <key>RunAtLoad</key>
        \\  <true/>
        \\  <key>KeepAlive</key>
        \\  <true/>
        \\</dict>
        \\</plist>
        \\
    );

    return buf.toOwnedSlice(allocator);
}

pub fn openUrl(allocator: std.mem.Allocator, url: []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, 2);
    result[0] = try allocator.dupe(u8, "open");
    result[1] = try allocator.dupe(u8, url);
    return result;
}

test "getDataDir" {
    const dir = try getDataDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Application Support/rawenv"));
}

test "getCacheDir" {
    const dir = try getCacheDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Caches/rawenv"));
}

test "getLogDir" {
    const dir = try getLogDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "Library/Logs/rawenv"));
}

test "launchdLabel" {
    const label = try launchdLabel(std.testing.allocator, "postgres");
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings("com.rawenv.postgres", label);
}

test "launchdPlist contains label and binary" {
    const args: []const []const u8 = &.{ "-D", "/data" };
    const plist = try launchdPlist(std.testing.allocator, "postgres", "/usr/bin/postgres", args, "/var/data");
    defer std.testing.allocator.free(plist);
    try std.testing.expect(std.mem.indexOf(u8, plist, "com.rawenv.postgres") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "/usr/bin/postgres") != null);
    try std.testing.expect(std.mem.indexOf(u8, plist, "<true/>") != null);
}

test "openUrl" {
    const args = try openUrl(std.testing.allocator, "https://example.com");
    defer {
        for (args) |a| std.testing.allocator.free(a);
        std.testing.allocator.free(args);
    }
    try std.testing.expectEqualStrings("open", args[0]);
    try std.testing.expectEqualStrings("https://example.com", args[1]);
}
