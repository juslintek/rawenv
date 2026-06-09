const std = @import("std");
const cell_mod = @import("cell.zig");

// Windows isolation uses AppContainer (process-level sandbox).
// Full implementation will use CreateAppContainerProfile / DeleteAppContainerProfile
// Win32 APIs to create a per-service AppContainer with restricted capabilities.
// For now this is a structural stub.

pub fn generateProfile(allocator: std.mem.Allocator, config: cell_mod.CellConfig) ![]const u8 {
    _ = config;
    return try allocator.dupe(u8, "# Windows AppContainer profile (stub)\n");
}
