const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const service = @import("service");

/// Build the modified PATH string: ~/.rawenv/bin:$PATH
pub fn buildPath(allocator: std.mem.Allocator, home: []const u8) ![]const u8 {
    const bin_path = try service.buildBinPath(allocator, home);
    defer allocator.free(bin_path);

    const sep: []const u8 = if (comptime builtin.os.tag == .windows) ";" else ":";
    const current_path = std.mem.sliceTo(std.c.getenv("PATH") orelse "", 0);
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ bin_path, sep, current_path });
}

/// Spawn a shell with modified environment
pub fn enter(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    const home = service.getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const new_path = try buildPath(allocator, home);
    defer allocator.free(new_path);

    // Get shell
    const shell: []const u8 = if (comptime builtin.os.tag == .windows)
        "cmd.exe"
    else
        if (std.c.getenv("SHELL")) |s| std.mem.sliceTo(s, 0) else "/bin/sh";

    try stdout.writeAll("Entering rawenv shell...\n");

    // Build env map
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();

    // Copy current env
    var sys_env = std.process.Environ.Map.init(allocator);
    defer sys_env.deinit();
    var it = sys_env.iterator();
    while (it.next()) |entry| {
        try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Override PATH
    try env_map.put("PATH", new_path);
    try env_map.put("RAWENV_ACTIVE", "1");
    try env_map.put("RAWENV_PROJECT", cfg.project_name);

    // Set service env vars
    for (cfg.services) |svc| {
        if (std.mem.eql(u8, svc.key, "postgresql") or std.mem.eql(u8, svc.key, "postgres")) {
            try env_map.put("DATABASE_URL", "postgresql://localhost:5432");
        } else if (std.mem.eql(u8, svc.key, "redis")) {
            try env_map.put("REDIS_URL", "redis://localhost:6379");
        }
    }

    // TODO: std.process.spawn requires Io in 0.16.0
    _ = shell;
    _ = &env_map;
    try stdout.writeAll("Error: shell spawn requires Io refactor for Zig 0.16.0\n");
}

test "buildPath" {
    const path = try buildPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);
    // Should start with the bin path
    try std.testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));
}
