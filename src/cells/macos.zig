const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;

pub const State = struct {
    profile_path: ?[]const u8 = null,
};

/// Generate a Seatbelt sandbox-exec profile string.
pub fn generateProfile(allocator: std.mem.Allocator, config: cell_mod.CellConfig) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.writeAll("(version 1)\n");
    try w.writeAll("(deny default)\n");
    try w.writeAll("(allow process-exec)\n");
    try w.writeAll("(allow process-fork)\n");
    try w.writeAll("(allow sysctl-read)\n");
    try w.print("(allow file-read* file-write* (subpath \"{s}\"))\n", .{config.data_dir});
    // Allow reading system libs needed for process execution
    try w.writeAll("(allow file-read* (subpath \"/usr/lib\") (subpath \"/usr/share\") (subpath \"/System\") (subpath \"/dev\"))\n");
    if (config.allowed_port > 0) {
        try w.print("(allow network* (local ip \"127.0.0.1:{d}\"))\n", .{config.allowed_port});
    }

    return buf.toOwnedSlice(allocator);
}

pub fn setup(self: *Cell) !void {
    // Write profile to a temp file in data_dir
    var path_buf: [512]u8 = undefined;
    const profile_path = std.fmt.bufPrint(&path_buf, "{s}/.rawenv_sandbox.sb", .{self.config.data_dir}) catch return error.NameTooLong;

    const profile = try generateProfile(self.allocator, self.config);
    defer self.allocator.free(profile);

    const file = std.fs.createFileAbsolute(profile_path, .{}) catch return error.ProfileWriteFailed;
    defer file.close();
    file.writeAll(profile) catch return error.ProfileWriteFailed;

    self.platform_state.profile_path = profile_path;
}

pub fn destroy(self: *Cell) void {
    if (self.platform_state.profile_path) |path| {
        std.fs.deleteFileAbsolute(path) catch {};
    }
    self.platform_state.profile_path = null;
}

/// Build argv for sandbox-exec invocation.
pub fn sandboxExecArgv(profile_path: []const u8, command: []const []const u8) [64]?[*:0]const u8 {
    var argv: [64]?[*:0]const u8 = .{null} ** 64;
    argv[0] = "sandbox-exec";
    argv[1] = "-f";
    argv[2] = @ptrCast(profile_path.ptr);
    argv[3] = "--";
    var i: usize = 4;
    for (command) |arg| {
        if (i >= 63) break;
        argv[i] = @ptrCast(arg.ptr);
        i += 1;
    }
    return argv;
}
