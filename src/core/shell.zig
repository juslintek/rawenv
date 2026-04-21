const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const service = @import("service");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

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
    const exec = @import("exec");

    const home = service.getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const new_path = try buildPath(allocator, home);
    defer allocator.free(new_path);

    const shell_path: []const u8 = if (comptime builtin.os.tag == .windows)
        "cmd.exe"
    else
        if (std.c.getenv("SHELL")) |s| std.mem.sliceTo(s, 0) else "/bin/sh";

    try stdout.writeAll("Entering rawenv shell (exit to return)...\n");

    // Set env vars before forking
    const path_z = try std.fmt.allocPrintSentinel(allocator, "{s}", .{new_path}, 0);
    defer allocator.free(path_z);
    _ = setenv("PATH", path_z, 1);
    _ = setenv("RAWENV_ACTIVE", "1", 1);

    const proj_z = try std.fmt.allocPrintSentinel(allocator, "{s}", .{cfg.project_name}, 0);
    defer allocator.free(proj_z);
    _ = setenv("RAWENV_PROJECT", proj_z, 1);

    // Set service env vars
    for (cfg.services) |svc| {
        if (std.mem.eql(u8, svc.key, "postgresql") or std.mem.eql(u8, svc.key, "postgres")) {
            _ = setenv("DATABASE_URL", "postgresql://localhost:5432", 1);
        } else if (std.mem.eql(u8, svc.key, "redis")) {
            _ = setenv("REDIS_URL", "redis://localhost:6379", 1);
        }
    }

    // Fork and exec the shell
    const shell_z = try std.fmt.allocPrintSentinel(allocator, "{s}", .{shell_path}, 0);
    defer allocator.free(shell_z);
    const argv = [_][*:0]const u8{shell_z};
    const exit_code = exec.run(&argv) catch {
        try stdout.writeAll("Error: failed to spawn shell\n");
        return;
    };
    _ = exit_code;
    try stdout.writeAll("Exited rawenv shell.\n");
}

test "buildPath" {
    const path = try buildPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);
    // Should start with the bin path
    try std.testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));
}
