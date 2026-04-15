const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const resolver = @import("resolver");

/// Get HOME directory path
pub fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return std.process.getEnvVarOwned(std.heap.page_allocator, "USERPROFILE") catch null;
    }
    return std.posix.getenv("HOME");
}

/// Build the store path for a runtime: ~/.rawenv/store/{name}-{version}
pub fn buildStorePath(allocator: std.mem.Allocator, home: []const u8, name: []const u8, version: []const u8) ![]const u8 {
    const dir_name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ name, version });
    defer allocator.free(dir_name);
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "store", dir_name });
}

/// Build the bin dir path: ~/.rawenv/bin
pub fn buildBinPath(allocator: std.mem.Allocator, home: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ home, ".rawenv", "bin" });
}

/// Activate all configured runtimes by creating symlinks in ~/.rawenv/bin/
pub fn up(allocator: std.mem.Allocator, cfg: config.Config, stdout: std.fs.File) !void {
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const bin_path = try buildBinPath(allocator, home);
    defer allocator.free(bin_path);

    // Create ~/.rawenv/bin/
    std.fs.makeDirAbsolute(std.fs.path.dirname(bin_path).?) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    std.fs.makeDirAbsolute(bin_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var activated: usize = 0;

    for (cfg.runtimes) |rt| {
        const full_version = resolver.resolveVersion(rt.key, rt.value);
        const store_path = try buildStorePath(allocator, home, rt.key, full_version);
        defer allocator.free(store_path);

        // Check if installed in store
        const store_bin = try std.fs.path.join(allocator, &.{ store_path, "bin", rt.key });
        defer allocator.free(store_bin);

        std.fs.accessAbsolute(store_bin, .{}) catch {
            try stdout.writeAll("  ");
            try stdout.writeAll(rt.key);
            try stdout.writeAll("@");
            try stdout.writeAll(rt.value);
            try stdout.writeAll(" — not installed, skipping\n");
            continue;
        };

        // Create symlink: ~/.rawenv/bin/{name} → store_bin
        const link_path = try std.fs.path.join(allocator, &.{ bin_path, rt.key });
        defer allocator.free(link_path);

        // Remove existing symlink if present
        std.fs.deleteFileAbsolute(link_path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        // Create symlink
        const bin_dir = try std.fs.openDirAbsolute(bin_path, .{});
        // symLink is not available on all platforms the same way; use symLinkAbsolute
        try std.fs.symLinkAbsolute(store_bin, link_path, .{});
        _ = bin_dir;

        try stdout.writeAll("  ✓ ");
        try stdout.writeAll(rt.key);
        try stdout.writeAll("@");
        try stdout.writeAll(rt.value);
        try stdout.writeAll(" activated\n");
        activated += 1;
    }

    if (activated == 0 and cfg.runtimes.len == 0) {
        try stdout.writeAll("No runtimes configured in rawenv.toml\n");
    } else if (activated > 0) {
        try stdout.writeAll("Done. Run `rawenv shell` to enter the environment.\n");
    }
}

/// List configured runtimes/services with status
pub fn list(allocator: std.mem.Allocator, cfg: config.Config, stdout: std.fs.File) !void {
    const home = getHome() orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    const bin_path = try buildBinPath(allocator, home);
    defer allocator.free(bin_path);

    if (cfg.runtimes.len == 0 and cfg.services.len == 0) {
        try stdout.writeAll("No runtimes or services configured.\n");
        return;
    }

    // Header
    try stdout.writeAll("NAME            VERSION    STATUS\n");
    try stdout.writeAll("──────────────  ─────────  ──────────────\n");

    for (cfg.runtimes) |rt| {
        try printEntry(allocator, stdout, home, bin_path, rt.key, rt.value);
    }
    for (cfg.services) |svc| {
        try printEntry(allocator, stdout, home, bin_path, svc.key, svc.value);
    }
}

fn printEntry(allocator: std.mem.Allocator, stdout: std.fs.File, home: []const u8, bin_path: []const u8, name: []const u8, version: []const u8) !void {
    const full_version = resolver.resolveVersion(name, version);
    const store_path = try buildStorePath(allocator, home, name, full_version);
    defer allocator.free(store_path);

    // Check installed
    const installed = blk: {
        std.fs.accessAbsolute(store_path, .{}) catch break :blk false;
        break :blk true;
    };

    // Check active (symlink exists)
    const active = blk: {
        const link_path = try std.fs.path.join(allocator, &.{ bin_path, name });
        defer allocator.free(link_path);
        std.fs.accessAbsolute(link_path, .{}) catch break :blk false;
        break :blk true;
    };

    const status: []const u8 = if (active) "active" else if (installed) "installed" else "not installed";

    // Print padded columns
    try stdout.writeAll(name);
    var pad: usize = if (name.len < 16) 16 - name.len else 2;
    for (0..pad) |_| try stdout.writeAll(" ");

    try stdout.writeAll(version);
    pad = if (version.len < 11) 11 - version.len else 2;
    for (0..pad) |_| try stdout.writeAll(" ");

    try stdout.writeAll(status);
    try stdout.writeAll("\n");
}

test "buildStorePath" {
    const path = try buildStorePath(std.testing.allocator, "/home/user", "node", "22.15.0");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/user/.rawenv/store/node-22.15.0", path);
}

test "buildBinPath" {
    const path = try buildBinPath(std.testing.allocator, "/home/user");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/home/user/.rawenv/bin", path);
}
