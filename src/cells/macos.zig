const std = @import("std");
const cell_mod = @import("cell.zig");

/// Generate a Seatbelt sandbox-exec profile string.
pub fn generateProfile(allocator: std.mem.Allocator, config: cell_mod.CellConfig) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "(version 1)\n(deny default)\n");
    try buf.appendSlice(allocator, "(allow process-exec)\n(allow process-fork)\n(allow sysctl-read)\n");
    try buf.print(allocator, "(allow file-read* file-write* (subpath \"{s}\"))\n", .{config.data_dir});
    try buf.appendSlice(allocator, "(allow file-read* (subpath \"/usr/lib\") (subpath \"/usr/share\") (subpath \"/System\") (subpath \"/dev\"))\n");
    if (config.allowed_port > 0) {
        try buf.print(allocator, "(allow network* (local ip \"127.0.0.1:{d}\"))\n", .{config.allowed_port});
    }

    return buf.toOwnedSlice(allocator);
}

/// Build argv for sandbox-exec: ["sandbox-exec", "-p", profile, "--"] ++ command
pub fn sandboxCommand(allocator: std.mem.Allocator, config: cell_mod.CellConfig, command: []const []const u8) ![]const []const u8 {
    const profile = try generateProfile(allocator, config);
    const argv = try allocator.alloc([]const u8, 4 + command.len);
    argv[0] = "sandbox-exec";
    argv[1] = "-p";
    argv[2] = profile; // caller must eventually free via allocator
    argv[3] = "--";
    @memcpy(argv[4..], command);
    return argv;
}
