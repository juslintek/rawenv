const std = @import("std");
const cell_mod = @import("cell.zig");

/// Generate a macOS Seatbelt (.sb) sandbox profile string.
pub fn generateSeatbeltProfile(allocator: std.mem.Allocator, config: cell_mod.CellConfig) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "(version 1)\n(deny default)\n");
    try buf.print(allocator, "(allow file-read* (subpath \"{s}\"))\n", .{config.data_dir});
    try buf.print(allocator, "(allow file-write* (subpath \"{s}\"))\n", .{config.data_dir});
    if (config.port > 0) {
        try buf.print(allocator, "(allow network* (local ip \"localhost:{d}\"))\n", .{config.port});
    }
    try buf.appendSlice(allocator, "(allow process-exec)\n");
    try buf.appendSlice(allocator, "(allow mach-lookup)\n");

    return buf.toOwnedSlice(allocator);
}

/// Build argv for sandbox-exec -f style invocation (inline profile via -p).
pub fn launchInSandbox(allocator: std.mem.Allocator, config: cell_mod.CellConfig, command: []const []const u8) ![]const []const u8 {
    const profile = try generateSeatbeltProfile(allocator, config);
    const argv = try allocator.alloc([]const u8, 4 + command.len);
    argv[0] = "sandbox-exec";
    argv[1] = "-p";
    argv[2] = profile;
    argv[3] = "--";
    @memcpy(argv[4..], command);
    return argv;
}
