const std = @import("std");
const cell_mod = @import("cell.zig");

pub const JobLimits = struct {
    process_memory: u64,
    active_processes: u32,
    limit_flags: u32,
};

pub const JOB_OBJECT_LIMIT_PROCESS_MEMORY: u32 = 0x00000100;
pub const JOB_OBJECT_LIMIT_ACTIVE_PROCESS: u32 = 0x00000008;

pub fn jobLimits(config: cell_mod.CellConfig) JobLimits {
    return .{
        .process_memory = @as(u64, config.mem_limit_mb) * 1024 * 1024,
        .active_processes = if (config.cpu_cores > 0) config.cpu_cores else 1,
        .limit_flags = JOB_OBJECT_LIMIT_PROCESS_MEMORY | JOB_OBJECT_LIMIT_ACTIVE_PROCESS,
    };
}

pub fn containerProfileName(buf: []u8, name: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "rawenv.cell.{s}", .{name}) catch name;
}
