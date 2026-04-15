const std = @import("std");
const builtin = @import("builtin");

pub const CellConfig = struct {
    name: []const u8,
    data_dir: []const u8,
    allowed_port: u16,
    mem_limit_mb: u32,
    cpu_cores: u32,
};

pub const CellStatus = enum { created, running, stopped, error_state };

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
    child: ?std.process.Child = null,

    pub fn create(allocator: std.mem.Allocator, config: CellConfig) Cell {
        return .{ .config = config, .status = .created, .allocator = allocator };
    }

    /// Build platform-wrapped argv and spawn the process.
    pub fn start(self: *Cell, command: []const []const u8) !void {
        if (self.status == .running) return;
        const argv = switch (builtin.os.tag) {
            .macos => try @import("macos.zig").sandboxCommand(self.allocator, self.config, command),
            else => try self.allocator.dupe([]const u8, command),
        };
        defer self.allocator.free(argv);

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .ignore;
        child.stdout_behavior = .ignore;
        child.stderr_behavior = .ignore;
        try child.spawn();
        self.child = child;
        self.status = .running;
    }

    pub fn stop(self: *Cell) void {
        if (self.child) |*ch| {
            _ = ch.kill() catch {};
            _ = ch.wait() catch {};
            self.child = null;
        }
        self.status = .stopped;
    }

    pub fn getStatus(self: *const Cell) CellStatus {
        return self.status;
    }

    pub fn destroy(self: *Cell) void {
        self.stop();
    }
};

pub fn createCell(allocator: std.mem.Allocator, config: CellConfig) !Cell {
    return Cell.create(allocator, config);
}
