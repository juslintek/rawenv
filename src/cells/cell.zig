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
    pid: ?std.posix.pid_t = null,

    pub fn create(allocator: std.mem.Allocator, config: CellConfig) Cell {
        return .{ .config = config, .status = .created, .allocator = allocator };
    }

    /// Build platform-wrapped argv and spawn the process.
    pub fn start(self: *Cell, command: []const []const u8) !void {
        if (self.status == .running) return;
        const exec = @import("exec");
        const argv = switch (builtin.os.tag) {
            .macos => try @import("macos.zig").sandboxCommand(self.allocator, self.config, command),
            else => try self.allocator.dupe([]const u8, command),
        };
        defer self.allocator.free(argv);

        // Convert to null-terminated sentinel pointers for exec.spawn
        var argv_z = try self.allocator.alloc([*:0]const u8, argv.len);
        defer self.allocator.free(argv_z);
        for (argv, 0..) |a, i| {
            argv_z[i] = try self.allocator.dupeZ(u8, a);
        }
        defer {
            for (argv_z) |a| self.allocator.free(std.mem.sliceTo(a, 0));
        }

        const pid = try exec.spawn(argv_z);
        self.pid = pid;
        self.status = .running;
    }

    pub fn stop(self: *Cell) void {
        if (self.pid) |pid| {
            if (comptime @import("builtin").os.tag != .windows)
                std.posix.kill(pid, std.posix.SIG.TERM) catch {};
            self.pid = null;
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
