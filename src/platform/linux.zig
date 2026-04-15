const std = @import("std");
const builtin = @import("builtin");

fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv("HOME");
}

pub fn getDataDir(allocator: std.mem.Allocator) ![]const u8 {
    if (comptime builtin.os.tag != .windows) {
        if (std.posix.getenv("XDG_DATA_HOME")) |xdg| {
            return std.fs.path.join(allocator, &.{ xdg, "rawenv" });
        }
    }
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".local", "share", "rawenv" });
}

pub fn getCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    if (comptime builtin.os.tag != .windows) {
        if (std.posix.getenv("XDG_CACHE_HOME")) |xdg| {
            return std.fs.path.join(allocator, &.{ xdg, "rawenv" });
        }
    }
    const home = getHome() orelse return error.HomeNotSet;
    return std.fs.path.join(allocator, &.{ home, ".cache", "rawenv" });
}

pub fn getLogDir(allocator: std.mem.Allocator) ![]const u8 {
    const data = try getDataDir(allocator);
    defer allocator.free(data);
    return std.fs.path.join(allocator, &.{ data, "logs" });
}

pub fn systemdUnitName(allocator: std.mem.Allocator, service_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "rawenv-{s}.service", .{service_name});
}

pub fn systemdUnit(allocator: std.mem.Allocator, service_name: []const u8, binary_path: []const u8, args: []const []const u8, data_dir: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("[Unit]\n");
    try w.print("Description=rawenv {s}\n\n", .{service_name});
    try w.writeAll("[Service]\nType=simple\n");
    try w.print("ExecStart={s}", .{binary_path});
    for (args) |arg| {
        try w.print(" {s}", .{arg});
    }
    try w.writeAll("\n");
    try w.print("WorkingDirectory={s}\n", .{data_dir});
    try w.writeAll("Restart=on-failure\n\n[Install]\nWantedBy=default.target\n");

    return buf.toOwnedSlice(allocator);
}

pub fn openUrl(allocator: std.mem.Allocator, url: []const u8) ![]const []const u8 {
    const result = try allocator.alloc([]const u8, 2);
    result[0] = try allocator.dupe(u8, "xdg-open");
    result[1] = try allocator.dupe(u8, url);
    return result;
}

test "getDataDir default" {
    const dir = try getDataDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "rawenv"));
}

test "getCacheDir default" {
    const dir = try getCacheDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "rawenv"));
}

test "getLogDir" {
    const dir = try getLogDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    try std.testing.expect(std.mem.endsWith(u8, dir, "logs"));
}

test "systemdUnitName" {
    const name = try systemdUnitName(std.testing.allocator, "postgres");
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("rawenv-postgres.service", name);
}

test "systemdUnit contains service info" {
    const args: []const []const u8 = &.{ "-D", "/data" };
    const unit = try systemdUnit(std.testing.allocator, "postgres", "/usr/bin/postgres", args, "/var/data");
    defer std.testing.allocator.free(unit);
    try std.testing.expect(std.mem.indexOf(u8, unit, "rawenv postgres") != null);
    try std.testing.expect(std.mem.indexOf(u8, unit, "/usr/bin/postgres -D /data") != null);
    try std.testing.expect(std.mem.indexOf(u8, unit, "Restart=on-failure") != null);
}

test "openUrl" {
    const args = try openUrl(std.testing.allocator, "https://example.com");
    defer {
        for (args) |a| std.testing.allocator.free(a);
        std.testing.allocator.free(args);
    }
    try std.testing.expectEqualStrings("xdg-open", args[0]);
    try std.testing.expectEqualStrings("https://example.com", args[1]);
}
