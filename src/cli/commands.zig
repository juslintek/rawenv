const std = @import("std");
const config = @import("config");
const detector = @import("detector");
const resolver = @import("resolver");
const store = @import("store");
const service = @import("service");
const shell = @import("shell");

pub fn runInit(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    const cwd = std.fs.cwd();

    // Check if rawenv.toml already exists
    if (cwd.access("rawenv.toml", .{})) |_| {
        try stdout.writeAll("rawenv.toml already exists — skipping.\n");
        return;
    } else |_| {}

    // Detect project
    var result = try detector.detect(allocator, cwd);
    defer result.deinit(allocator);

    // Derive project name from cwd
    const cwd_path = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd_path);
    const project_name = std.fs.path.basename(cwd_path);

    // Generate TOML
    const rt_entries: []const config.Config.Entry = @ptrCast(result.runtimes);
    const svc_entries: []const config.Config.Entry = @ptrCast(result.services);
    const toml = try config.generate(allocator, project_name, rt_entries, svc_entries);
    defer allocator.free(toml);

    // Write file
    const file = try cwd.createFile("rawenv.toml", .{});
    defer file.close();
    try file.writeAll(toml);

    // Print summary
    try stdout.writeAll("Created rawenv.toml\n");
    if (result.runtimes.len > 0) {
        try stdout.writeAll("Detected runtimes:\n");
        for (result.runtimes) |rt| {
            try stdout.writeAll("  ");
            try stdout.writeAll(rt.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(rt.value);
            try stdout.writeAll("\n");
        }
    }
    if (result.services.len > 0) {
        try stdout.writeAll("Detected services:\n");
        for (result.services) |svc| {
            try stdout.writeAll("  ");
            try stdout.writeAll(svc.key);
            try stdout.writeAll(" ");
            try stdout.writeAll(svc.value);
            try stdout.writeAll("\n");
        }
    }
}

pub fn runAdd(allocator: std.mem.Allocator, stdout: std.fs.File, package_spec: []const u8) !void {
    const parsed = resolver.parsePackageSpec(package_spec) orelse {
        try stdout.writeAll("Usage: rawenv add <package>@<version>\n");
        try stdout.writeAll("Example: rawenv add node@22\n");
        return;
    };

    const pkg = resolver.resolve(allocator, parsed.name, parsed.version) catch |err| {
        switch (err) {
            error.UnknownPackage => try stdout.writeAll("Error: unknown package\n"),
            error.UnknownVersion => try stdout.writeAll("Error: unknown version\n"),
            error.UnsupportedPlatform => try stdout.writeAll("Error: unsupported platform\n"),
            error.OutOfMemory => try stdout.writeAll("Error: out of memory\n"),
        }
        return;
    };
    defer allocator.free(pkg.url);

    store.add(allocator, pkg, stdout) catch |err| {
        switch (err) {
            error.Sha256Mismatch => try stdout.writeAll("Error: SHA256 verification failed\n"),
            error.DownloadFailed => try stdout.writeAll("Error: download failed\n"),
            error.ExtractionFailed => try stdout.writeAll("Error: extraction failed\n"),
            error.HomeNotSet => try stdout.writeAll("Error: HOME environment variable not set\n"),
            else => try stdout.writeAll("Error: installation failed\n"),
        }
    };
}

fn loadConfig(allocator: std.mem.Allocator, stdout: std.fs.File) !?struct { cfg: config.Config, toml: []const u8 } {
    const toml = std.fs.cwd().readFileAlloc(allocator, "rawenv.toml", 1024 * 64) catch {
        try stdout.writeAll("Error: rawenv.toml not found. Run `rawenv init` first.\n");
        return null;
    };

    const cfg = config.parse(allocator, toml) catch {
        allocator.free(toml);
        try stdout.writeAll("Error: failed to parse rawenv.toml\n");
        return null;
    };

    return .{ .cfg = cfg, .toml = toml };
}

pub fn runUp(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    try service.up(allocator, result.cfg, stdout);
}

pub fn runServicesList(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    try service.list(allocator, result.cfg, stdout);
}

pub fn runShell(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);
    try shell.enter(allocator, result.cfg, stdout);
}
