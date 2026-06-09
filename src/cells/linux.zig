const std = @import("std");
const cell_mod = @import("cell.zig");

/// Generate a systemd unit file for sandboxed service execution.
pub fn generateSystemdUnit(allocator: std.mem.Allocator, config: cell_mod.CellConfig, binary_path: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "[Unit]\n");
    try buf.print(allocator, "Description=rawenv cell: {s}\n\n", .{config.service_name});
    try buf.appendSlice(allocator, "[Service]\n");
    try buf.print(allocator, "ExecStart={s}\n", .{binary_path});
    try buf.appendSlice(allocator, "ProtectSystem=strict\n");
    try buf.print(allocator, "ReadWritePaths={s}\n", .{config.data_dir});
    try buf.appendSlice(allocator, "PrivateNetwork=yes\n");
    try buf.print(allocator, "MemoryMax={d}M\n", .{config.memory_limit_mb});
    try buf.print(allocator, "CPUQuota={d}%\n\n", .{@as(u32, config.cpu_cores) * 100});
    try buf.appendSlice(allocator, "[Install]\n");
    try buf.appendSlice(allocator, "WantedBy=multi-user.target\n");

    return buf.toOwnedSlice(allocator);
}
