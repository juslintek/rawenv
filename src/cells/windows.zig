const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;

pub const State = struct {
    container_name: ?[]const u8 = null,
    job_handle: ?std.os.windows.HANDLE = null,
};

pub const JobLimits = struct {
    process_memory: u64,
    active_processes: u32,
};

pub fn computeJobLimits(config: cell_mod.CellConfig) JobLimits {
    return .{
        .process_memory = @as(u64, config.mem_limit_mb) * 1024 * 1024,
        .active_processes = if (config.cpu_cores > 0) config.cpu_cores else 1,
    };
}

/// JOB_OBJECT_LIMIT flags
pub const JOB_OBJECT_LIMIT_PROCESS_MEMORY: u32 = 0x00000100;
pub const JOB_OBJECT_LIMIT_ACTIVE_PROCESS: u32 = 0x00000008;

pub fn setup(self: *Cell) !void {
    self.platform_state.container_name = self.config.name;
    // On actual Windows, would call:
    // CreateAppContainerProfile(name, name, name, null, 0, &sid)
    // CreateJobObjectW(null, name)
    // SetInformationJobObject(job, .ExtendedLimitInformation, &info)
}

pub fn destroy(self: *Cell) void {
    // On actual Windows, would call:
    // DeleteAppContainerProfile(name)
    // CloseHandle(job_handle)
    if (self.platform_state.job_handle) |h| {
        std.os.windows.CloseHandle(h);
    }
    self.platform_state.container_name = null;
    self.platform_state.job_handle = null;
}

/// Generate the container profile name for AppContainer.
pub fn containerProfileName(buf: []u8, name: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "rawenv.cell.{s}", .{name}) catch name;
}
