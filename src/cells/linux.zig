const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;

pub const State = struct {
    cgroup_path: ?[]const u8 = null,
};

pub const CgroupConfig = struct {
    memory_max: []const u8,
    cpu_max: []const u8,
};

pub fn generateCgroupConfig(config: cell_mod.CellConfig) CgroupConfig {
    return .{
        .memory_max = if (config.mem_limit_mb > 0) blk: {
            // Return a static representation; actual write uses fmt
            break :blk "memory.max";
        } else "max",
        .cpu_max = if (config.cpu_cores > 0) "cpu.max" else "max",
    };
}

pub fn writeCgroupMemory(buf: []u8, mem_limit_mb: u32) []const u8 {
    const bytes: u64 = @as(u64, mem_limit_mb) * 1024 * 1024;
    return std.fmt.bufPrint(buf, "{d}", .{bytes}) catch "max";
}

pub fn writeCgroupCpu(buf: []u8, cpu_cores: u32) []const u8 {
    const quota = @as(u64, cpu_cores) * 100000;
    return std.fmt.bufPrint(buf, "{d} 100000", .{quota}) catch "max 100000";
}

pub fn setup(self: *Cell) !void {
    const cgroup_base = "/sys/fs/cgroup/rawenv_";
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ cgroup_base, self.config.name }) catch return error.NameTooLong;

    // Try to create cgroup directory
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.AccessDenied => {}, // Expected without root
        error.PathAlreadyExists => {},
        else => return err,
    };

    self.platform_state.cgroup_path = path;

    // Write memory limit
    if (self.config.mem_limit_mb > 0) {
        var mem_buf: [32]u8 = undefined;
        const mem_val = writeCgroupMemory(&mem_buf, self.config.mem_limit_mb);
        writeCgroupFile(path, "memory.max", mem_val) catch {};
    }

    // Write CPU limit
    if (self.config.cpu_cores > 0) {
        var cpu_buf: [32]u8 = undefined;
        const cpu_val = writeCgroupCpu(&cpu_buf, self.config.cpu_cores);
        writeCgroupFile(path, "cpu.max", cpu_val) catch {};
    }
}

fn writeCgroupFile(cgroup_path: []const u8, filename: []const u8, value: []const u8) !void {
    var path_buf: [512]u8 = undefined;
    const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ cgroup_path, filename }) catch return;
    const file = std.fs.openFileAbsolute(full_path, .{ .mode = .write_only }) catch return;
    defer file.close();
    file.writeAll(value) catch {};
}

pub fn destroy(self: *Cell) void {
    if (self.platform_state.cgroup_path) |path| {
        std.fs.deleteDirAbsolute(path) catch {};
    }
    self.platform_state.cgroup_path = null;
}

/// Landlock: restrict filesystem access to data_dir only.
/// Returns error if kernel doesn't support Landlock.
pub fn applyLandlock(data_dir: []const u8) !void {
    const linux = std.os.linux;
    const LANDLOCK_CREATE_RULESET = 444;
    const LANDLOCK_ADD_RULE = 445;
    const LANDLOCK_RESTRICT_SELF = 446;

    const LANDLOCK_ACCESS_FS_READ: u64 = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40;
    const LANDLOCK_ACCESS_FS_WRITE: u64 = 0x80 | 0x100 | 0x200 | 0x400 | 0x800;
    const all_access = LANDLOCK_ACCESS_FS_READ | LANDLOCK_ACCESS_FS_WRITE;

    // Create ruleset
    const RulesetAttr = extern struct {
        handled_access_fs: u64,
        handled_access_net: u64 = 0,
        scoped: u64 = 0,
    };
    var attr = RulesetAttr{ .handled_access_fs = all_access };
    const fd = linux.syscall3(LANDLOCK_CREATE_RULESET, @intFromPtr(&attr), @sizeOf(RulesetAttr), 0);
    if (@as(isize, @bitCast(fd)) < 0) return error.LandlockNotSupported;

    // Add rule for data_dir
    const dir_fd_result = std.fs.openDirAbsolute(data_dir, .{}) catch return error.DataDirNotFound;
    defer dir_fd_result.close();

    const PathBeneath = extern struct {
        allowed_access: u64,
        parent_fd: i32,
        padding: i32 = 0,
    };
    var rule = PathBeneath{
        .allowed_access = all_access,
        .parent_fd = dir_fd_result.fd,
    };
    _ = linux.syscall4(LANDLOCK_ADD_RULE, fd, 1, @intFromPtr(&rule), 0);

    // Restrict self
    _ = linux.syscall3(LANDLOCK_RESTRICT_SELF, fd, 0, 0);
}

/// Clone flags for user namespace isolation
pub const CLONE_NEWUSER: u32 = 0x10000000;
pub const CLONE_NEWPID: u32 = 0x20000000;
pub const CLONE_NEWNS: u32 = 0x00020000;
pub const NAMESPACE_FLAGS: u32 = CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWNS;
