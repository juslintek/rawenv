const std = @import("std");
const builtin = @import("builtin");

pub const CellConfig = struct {
    service_name: []const u8,
    data_dir: []const u8,
    port: u16,
    memory_limit_mb: u32,
    cpu_cores: u8,
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
    is_running: bool,
    pid: ?std.process.Child.Id,
    allocator: std.mem.Allocator,
    child: ?std.process.Child = null,

    pub fn start(self: *Cell, command: []const []const u8) !void {
        if (self.is_running) return;
        const argv = switch (builtin.os.tag) {
            .macos => try @import("macos.zig").launchInSandbox(self.allocator, self.config, command),
            else => try self.allocator.dupe([]const u8, command),
        };
        defer self.allocator.free(argv);

        var child = std.process.Child.init(argv, self.allocator);
        child.stdin_behavior = .ignore;
        child.stdout_behavior = .ignore;
        child.stderr_behavior = .ignore;
        try child.spawn();
        self.child = child;
        self.pid = child.id;
        self.is_running = true;
    }

    pub fn stop(self: *Cell) void {
        if (self.child) |*ch| {
            if (ch.id) |pid| {
                if (comptime builtin.os.tag != .windows)
                    std.posix.kill(pid, .TERM) catch {};
            }
            self.child = null;
        }
        self.is_running = false;
        self.pid = null;
    }

    pub fn destroy(self: *Cell) void {
        self.stop();
    }
};

pub fn createCell(allocator: std.mem.Allocator, config: CellConfig) Cell {
    return .{ .config = config, .is_running = false, .pid = null, .allocator = allocator };
}

/// Build a CellConfig from a resolved service instance (port + per-instance data dir).
pub fn configFor(service_name: []const u8, data_dir: []const u8, port: u16) CellConfig {
    return .{
        .service_name = service_name,
        .data_dir = data_dir,
        .port = port,
        .memory_limit_mb = 512,
        .cpu_cores = 1,
    };
}

/// Delegates to platform-specific profile generation.
pub fn generateProfile(allocator: std.mem.Allocator, config: CellConfig) ![]const u8 {
    return switch (builtin.os.tag) {
        .macos => try @import("macos.zig").generateSeatbeltProfile(allocator, config),
        .linux => try @import("linux.zig").generateSystemdUnit(allocator, config, ""),
        else => try allocator.dupe(u8, "# no isolation profile for this platform\n"),
    };
}
