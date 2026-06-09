const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const service = @import("service");

pub const ShellType = enum { zsh, bash, fish };

/// Build the modified PATH string: ~/.rawenv/bin:$PATH
pub fn buildPath(allocator: std.mem.Allocator, home: []const u8) ![]const u8 {
    const bin_path = try service.buildBinPath(allocator, home);
    defer allocator.free(bin_path);
    const sep: []const u8 = if (comptime builtin.os.tag == .windows) ";" else ":";
    const current_path = if (comptime builtin.os.tag == .windows) "" else std.mem.sliceTo(std.c.getenv("PATH") orelse "", 0);
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ bin_path, sep, current_path });
}

/// Generate environment variables for configured services.
pub fn generateEnvVars(allocator: std.mem.Allocator, cfg: config.Config) ![]const [2][]const u8 {
    var list: std.ArrayList([2][]const u8) = .empty;
    try list.append(allocator, .{ "RAWENV_ACTIVE", "1" });
    try list.append(allocator, .{ "RAWENV_PROJECT", cfg.project_name });

    for (cfg.services) |svc| {
        if (std.mem.eql(u8, svc.key, "postgresql") or std.mem.eql(u8, svc.key, "postgres")) {
            try list.append(allocator, .{ "DATABASE_URL", "postgresql://localhost:5432" });
        } else if (std.mem.eql(u8, svc.key, "redis")) {
            try list.append(allocator, .{ "REDIS_URL", "redis://localhost:6379" });
        } else if (std.mem.eql(u8, svc.key, "meilisearch")) {
            try list.append(allocator, .{ "MEILISEARCH_URL", "http://localhost:7700" });
        }
    }
    return list.toOwnedSlice(allocator);
}

/// Get shell RC lines to add to config file.
pub fn getShellRC(allocator: std.mem.Allocator, shell_type: ShellType) ![]const u8 {
    return switch (shell_type) {
        .zsh, .bash => try allocator.dupe(u8, "export PATH=\"$HOME/.rawenv/bin:$PATH\"\n"),
        .fish => try allocator.dupe(u8, "set -gx PATH $HOME/.rawenv/bin $PATH\n"),
    };
}

/// Activate a real shell with modified environment (replaces current process on Unix)
pub fn activateShell(allocator: std.mem.Allocator, cfg: config.Config) !void {
    if (comptime builtin.os.tag == .windows) return;

    const home = service.getHome() orelse return;
    const new_path = try buildPath(allocator, home);

    const env_vars = try generateEnvVars(allocator, cfg);

    const shell = std.mem.sliceTo(std.c.getenv("SHELL") orelse "/bin/sh", 0);

    // Build envp: copy current env, override PATH, add rawenv vars
    var env_list: std.ArrayList(?[*:0]const u8) = .empty;

    // Copy existing environment, skipping keys we'll override
    const environ: [*:null]const ?[*:0]const u8 = std.c.environ;
    var i: usize = 0;
    while (environ[i]) |entry| : (i += 1) {
        const s = std.mem.sliceTo(entry, 0);
        var skip = false;
        if (std.mem.startsWith(u8, s, "PATH=")) skip = true;
        for (env_vars) |pair| {
            if (std.mem.startsWith(u8, s, pair[0]) and s.len > pair[0].len and s[pair[0].len] == '=') {
                skip = true;
                break;
            }
        }
        if (!skip) try env_list.append(allocator, entry);
    }

    // Add PATH
    const path_entry = try std.fmt.allocPrintSentinel(allocator, "PATH={s}", .{new_path}, 0);
    try env_list.append(allocator, path_entry);

    // Add rawenv vars
    for (env_vars) |pair| {
        const entry = try std.fmt.allocPrintSentinel(allocator, "{s}={s}", .{ pair[0], pair[1] }, 0);
        try env_list.append(allocator, entry);
    }

    // Null-terminate the envp array
    try env_list.append(allocator, null);
    const envp_slice = try env_list.toOwnedSlice(allocator);
    const envp: [*:null]const ?[*:0]const u8 = @ptrCast(envp_slice.ptr);

    // Build argv
    const shell_z = try allocator.dupeZ(u8, shell);
    const argv = [_:null]?[*:0]const u8{shell_z.ptr};
    const argv_ptr: [*:null]const ?[*:0]const u8 = &argv;

    // execve replaces the current process — does not return on success
    _ = std.c.execve(shell_z.ptr, argv_ptr, envp);
}

/// Spawn a shell with modified environment (print info + exec)
pub fn enter(allocator: std.mem.Allocator, cfg: config.Config, stdout: anytype) !void {
    const home = service.getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const new_path = try buildPath(allocator, home);
    defer allocator.free(new_path);

    try stdout.writeAll("Entering rawenv shell (");
    try stdout.writeAll(cfg.project_name);
    try stdout.writeAll(")...\n");

    const env_vars = try generateEnvVars(allocator, cfg);
    defer allocator.free(env_vars);

    for (env_vars) |pair| {
        try stdout.writeAll("  ");
        try stdout.writeAll(pair[0]);
        try stdout.writeAll("=");
        try stdout.writeAll(pair[1]);
        try stdout.writeAll("\n");
    }

    try stdout.writeAll("  PATH=");
    try stdout.writeAll(new_path);
    try stdout.writeAll("\n");

    // Actually exec the shell (replaces this process)
    try activateShell(allocator, cfg);
}

test "buildPath" {
    const path = try buildPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.startsWith(u8, path, "/home/user/.rawenv/bin:"));
}

test "getShellRC zsh" {
    const rc = try getShellRC(std.testing.allocator, .zsh);
    defer std.testing.allocator.free(rc);
    try std.testing.expect(std.mem.indexOf(u8, rc, "export PATH") != null);
}

test "getShellRC fish" {
    const rc = try getShellRC(std.testing.allocator, .fish);
    defer std.testing.allocator.free(rc);
    try std.testing.expect(std.mem.indexOf(u8, rc, "set -gx PATH") != null);
}
