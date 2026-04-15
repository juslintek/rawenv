const std = @import("std");
const builtin = @import("builtin");

pub const CellConfig = struct {
    name: []const u8,
    data_dir: []const u8,
    allowed_port: u16,
    mem_limit_mb: u32,
    cpu_cores: u32,
};

pub const CellStatus = enum { running, stopped, error_state };

pub const platform = switch (builtin.os.tag) {
    .linux => @import("linux.zig"),
    .macos => @import("macos.zig"),
    .windows => @import("windows.zig"),
    else => struct {},
};

pub const Cell = struct {
    config: CellConfig,
    status: CellStatus,
    allocator: std.mem.Allocator,
    /// Platform-specific opaque state
    platform_state: PlatformState,

    const PlatformState = switch (builtin.os.tag) {
        .linux => @import("linux.zig").State,
        .macos => @import("macos.zig").State,
        .windows => @import("windows.zig").State,
        else => void,
    };

    pub fn getStatus(self: *const Cell) CellStatus {
        return self.status;
    }

    pub fn destroy(self: *Cell) void {
        switch (builtin.os.tag) {
            .linux => @import("linux.zig").destroy(self),
            .macos => @import("macos.zig").destroy(self),
            .windows => @import("windows.zig").destroy(self),
            else => {},
        }
        self.status = .stopped;
    }
};

pub fn createCell(allocator: std.mem.Allocator, config: CellConfig) !Cell {
    var cell = Cell{
        .config = config,
        .status = .stopped,
        .allocator = allocator,
        .platform_state = switch (builtin.os.tag) {
            .linux => .{},
            .macos => .{},
            .windows => .{},
            else => {},
        },
    };

    switch (builtin.os.tag) {
        .linux => try @import("linux.zig").setup(&cell),
        .macos => try @import("macos.zig").setup(&cell),
        .windows => try @import("windows.zig").setup(&cell),
        else => {},
    }

    cell.status = .running;
    return cell;
}
