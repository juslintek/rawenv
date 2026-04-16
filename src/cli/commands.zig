const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");
const detector = @import("detector");
const resolver = @import("resolver");
const store = @import("store");
const service = @import("service");
const shell = @import("shell");
const dns = @import("dns");
const proxy = @import("proxy");
const tunnel = @import("tunnel");
const connections = @import("connections");
const cell = @import("cell");
const discover = @import("discover");

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

pub fn runDns(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var svc_names: std.ArrayList([]const u8) = .empty;
    defer svc_names.deinit(allocator);
    for (result.cfg.services) |svc| try svc_names.append(allocator, svc.key);

    const cfg = dns.DnsConfig{
        .project = result.cfg.project_name,
        .services = svc_names.items,
    };
    const entries = try dns.generateHostsEntries(allocator, cfg);
    defer allocator.free(entries);
    try stdout.writeAll(entries);
}

pub fn runProxy(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var p = proxy.Proxy.init(allocator);
    defer p.deinit();

    var port: u16 = 3000;
    for (result.cfg.services) |svc| {
        try p.addRoute(svc.key, port);
        port += 1;
    }

    const caddy = try p.generateCaddyConfig(allocator);
    defer allocator.free(caddy);
    try stdout.writeAll(caddy);
}

pub fn runTunnel(allocator: std.mem.Allocator, stdout: std.fs.File, port_str: []const u8) !void {
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        try stdout.writeAll("Error: invalid port number\n");
        return;
    };
    const cfg = tunnel.TunnelConfig{
        .local_port = port,
        .ssh_host = "tunnel.example.com",
        .ssh_user = "rawenv",
    };
    const cmd = try cfg.generateSshCommand(allocator);
    defer allocator.free(cmd);
    try stdout.writeAll(cmd);
    try stdout.writeAll("\n");
}

pub fn runConnections(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    var result = (try loadConfig(allocator, stdout)) orelse return;
    defer allocator.free(result.toml);
    defer config.deinit(allocator, &result.cfg);

    var map = connections.ConnectionMap.init(allocator);
    defer map.deinit();
    try map.parseServiceDeps(result.toml);

    if (map.count() == 0) {
        try stdout.writeAll("No service dependencies found.\n");
        return;
    }
    for (map.links.items) |link| {
        try stdout.writeAll(link.from);
        try stdout.writeAll(" -> ");
        try stdout.writeAll(link.to);
        try stdout.writeAll("\n");
    }
}

pub fn runCellInfo(_: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Isolation backends available on this OS:\n");
    switch (builtin.os.tag) {
        .macos => try stdout.writeAll("  seatbelt (sandbox-exec) — macOS App Sandbox\n"),
        .linux => {
            try stdout.writeAll("  cgroups v2 — memory/CPU limits\n");
            try stdout.writeAll("  namespaces — PID/mount/network isolation\n");
            try stdout.writeAll("  landlock — filesystem restriction\n");
        },
        .windows => try stdout.writeAll("  job objects — process memory/CPU limits\n"),
        else => try stdout.writeAll("  none — unsupported OS\n"),
    }
}

pub fn runMenubar(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    const macos = @import("macos");
    if (comptime builtin.os.tag == .macos) {
        try macos.runMenuBar(allocator);
    } else {
        try stdout.writeAll("Menu bar is only available on macOS\n");
    }
}

pub fn runDiscover(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    const results = discover.discover(allocator) catch {
        try stdout.writeAll("Error: discovery failed\n");
        return;
    };
    defer discover.freeResults(allocator, results);

    if (results.len == 0) {
        try stdout.writeAll("No projects found.\n");
        return;
    }
    for (results) |p| {
        try stdout.writeAll(p.path);
        try stdout.writeAll(" [");
        try stdout.writeAll(p.stack);
        if (p.has_rawenv_toml) try stdout.writeAll(", rawenv");
        try stdout.writeAll("]\n");
    }
}

pub fn runUninstall(_: std.mem.Allocator, stdout: std.fs.File) !void {
    const home = std.posix.getenv("HOME") orelse {
        try stdout.writeAll("Error: HOME not set\n");
        return;
    };

    try stdout.writeAll("rawenv uninstall will remove:\n");
    try stdout.writeAll("  ");
    try stdout.writeAll(home);
    try stdout.writeAll("/.rawenv/bin/\n");
    try stdout.writeAll("  ");
    try stdout.writeAll(home);
    try stdout.writeAll("/.rawenv/store/\n");
    try stdout.writeAll("  PATH entries from .zshrc, .bashrc, .profile\n");
    try stdout.writeAll("\nProceed? [y/N] ");

    const stdin = std.fs.File.stdin();
    var buf: [16]u8 = undefined;
    const n = stdin.read(&buf) catch 0;
    if (n == 0) return;
    const answer = std.mem.trimRight(u8, buf[0..n], "\r\n");
    if (!std.mem.eql(u8, answer, "y") and !std.mem.eql(u8, answer, "Y")) {
        try stdout.writeAll("Aborted.\n");
        return;
    }

    // Remove ~/.rawenv/
    var rawenv_path_buf: [1024]u8 = undefined;
    const rawenv_path = std.fmt.bufPrint(&rawenv_path_buf, "{s}/.rawenv", .{home}) catch return;
    std.fs.cwd().deleteTree(rawenv_path) catch |err| {
        if (err != error.FileNotFound) {
            try stdout.writeAll("Warning: could not fully remove ");
            try stdout.writeAll(rawenv_path);
            try stdout.writeAll("\n");
        }
    };

    // Clean shell rc files
    const rc_files = [_][]const u8{ ".zshrc", ".bashrc", ".profile" };
    for (rc_files) |rc| {
        cleanRcFile(home, rc) catch {};
    }

    try stdout.writeAll("rawenv uninstalled\n");
}

fn cleanRcFile(home: []const u8, filename: []const u8) !void {
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, filename }) catch return;

    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();

    const stat = file.stat() catch return;
    if (stat.size == 0 or stat.size > 64 * 1024) return;

    var content_buf: [64 * 1024]u8 = undefined;
    const n = file.readAll(&content_buf) catch return;
    const content = content_buf[0..n];

    var out_buf: [64 * 1024]u8 = undefined;
    var out_len: usize = 0;
    var start: usize = 0;
    while (start < content.len) {
        const end = std.mem.indexOfScalar(u8, content[start..], '\n');
        const line_end = if (end) |e| start + e else content.len;
        const line = content[start..line_end];
        if (std.mem.indexOf(u8, line, "rawenv") == null) {
            if (out_len + line.len + 1 > out_buf.len) return;
            @memcpy(out_buf[out_len .. out_len + line.len], line);
            out_len += line.len;
            out_buf[out_len] = '\n';
            out_len += 1;
        }
        start = line_end + 1;
    }

    const out_file = std.fs.cwd().createFile(path, .{}) catch return;
    defer out_file.close();
    out_file.writeAll(out_buf[0..out_len]) catch {};
}
