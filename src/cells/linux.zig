const std = @import("std");
const cell_mod = @import("cell.zig");

pub const CgroupSettings = struct {
    memory_max_bytes: u64,
    cpu_quota: u64,
    cpu_period: u64,
};

pub fn cgroupConfig(config: cell_mod.CellConfig) CgroupSettings {
    return .{
        .memory_max_bytes = @as(u64, config.mem_limit_mb) * 1024 * 1024,
        .cpu_quota = @as(u64, config.cpu_cores) * 100000,
        .cpu_period = 100000,
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

/// Clone flags for namespace isolation.
pub const CLONE_NEWUSER: u32 = 0x10000000;
pub const CLONE_NEWPID: u32 = 0x20000000;
pub const CLONE_NEWNS: u32 = 0x00020000;
pub const CLONE_NEWNET: u32 = 0x40000000;
pub const NAMESPACE_FLAGS: u32 = CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWNS | CLONE_NEWNET;

pub fn namespaceFlags(config: cell_mod.CellConfig) u32 {
    var flags: u32 = CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWNS;
    if (config.allowed_port > 0) flags |= CLONE_NEWNET;
    return flags;
}

/// Landlock path-restriction config (no actual syscalls).
pub const LandlockConfig = struct {
    data_dir: []const u8,
    read_only_paths: []const []const u8,
};

pub fn landlockConfig(config: cell_mod.CellConfig) LandlockConfig {
    return .{
        .data_dir = config.data_dir,
        .read_only_paths = &.{ "/usr/lib", "/usr/share", "/lib", "/lib64" },
    };
}
