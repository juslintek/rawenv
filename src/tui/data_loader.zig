const std = @import("std");
const builtin = @import("builtin");
const app = @import("app.zig");

/// Known version mappings (mirrors resolver.resolveVersion without importing it)
fn resolveVersion(name: []const u8, version: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "node")) {
        if (std.mem.eql(u8, version, "22")) return "22.15.0";
        if (std.mem.eql(u8, version, "20")) return "20.18.3";
        if (std.mem.eql(u8, version, "18")) return "18.20.8";
    }
    return version;
}

/// Parsed entry from rawenv.toml [services.X] sections
const TomlService = struct {
    name: []const u8,
    version: []const u8,
};

/// Parse rawenv.toml from cwd. Returns list of service entries.
fn parseToml(allocator: std.mem.Allocator, content: []const u8) ![]TomlService {
    var result: std.ArrayList(TomlService) = .empty;
    errdefer result.deinit(allocator);

    var current_service: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, &std.ascii.whitespace);
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            const section = line[1 .. line.len - 1];
            if (std.mem.startsWith(u8, section, "services.")) {
                current_service = section["services.".len..];
            } else {
                current_service = null;
            }
            continue;
        }

        if (current_service) |svc_name| {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], &std.ascii.whitespace);
            if (std.mem.eql(u8, key, "version")) {
                var val = std.mem.trim(u8, line[eq + 1 ..], &std.ascii.whitespace);
                if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"')
                    val = val[1 .. val.len - 1];
                try result.append(allocator, .{ .name = svc_name, .version = val });
            }
        }
    }
    return result.toOwnedSlice(allocator);
}

/// Check if a service is installed in ~/.rawenv/store/{name}-{version}
fn isInstalled(home: []const u8, name: []const u8, version: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/.rawenv/store/{s}-{s}", .{ home, name, version }) catch return false;
    return std.c.access(path, 0) == 0;
}

/// Check if a service is active (symlink in ~/.rawenv/bin/{name})
fn isActive(home: []const u8, name: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/.rawenv/bin/{s}", .{ home, name }) catch return false;
    return std.c.access(path, 0) == 0;
}

/// Try to get PID of a running process by name via `pgrep`
fn getPid(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    _ = allocator;
    _ = name;
    // std.process.Child.run requires Io in 0.16.0; skip process lookup
    return null;
}

/// Get CPU/MEM for a PID via `ps -p PID -o %cpu,%mem`
const PsStats = struct { cpu: []const u8, mem: []const u8 };

fn getPsStats(allocator: std.mem.Allocator, pid: []const u8) ?PsStats {
    _ = allocator;
    _ = pid;
    // std.process.Child.run requires Io in 0.16.0; skip stats lookup
    return null;
}

/// Read last N lines from a log file
fn readLogTail(allocator: std.mem.Allocator, path: []const u8, max_lines: usize) ?[]app.LogEntry {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return null;
    defer _ = std.c.close(fd);
    var content_buf: std.ArrayList(u8) = .empty;
    defer content_buf.deinit(allocator);
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &read_buf) catch return null;
        if (n == 0) break;
        content_buf.appendSlice(allocator, read_buf[0..n]) catch return null;
    }
    const content = content_buf.toOwnedSlice(allocator) catch return null;
    defer allocator.free(content);

    var entries: std.ArrayList(app.LogEntry) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    // Collect all lines first
    var all_lines: std.ArrayList([]const u8) = .empty;
    defer all_lines.deinit(allocator);
    while (lines.next()) |line| {
        if (line.len > 0) all_lines.append(allocator, line) catch continue;
    }
    // Take last max_lines
    const start = if (all_lines.items.len > max_lines) all_lines.items.len - max_lines else 0;
    for (all_lines.items[start..]) |line| {
        entries.append(allocator, .{
            .time = allocator.dupe(u8, if (line.len >= 8) line[0..8] else line) catch continue,
            .level = "normal",
            .msg = allocator.dupe(u8, line) catch continue,
        }) catch continue;
    }
    return entries.toOwnedSlice(allocator) catch null;
}

/// Load real services from rawenv.toml + filesystem status
pub fn loadServices(allocator: std.mem.Allocator) ?[]app.Service {
    if (comptime builtin.os.tag == .windows) return null;

    const home = std.mem.sliceTo(std.c.getenv("HOME") orelse return null, 0);

    // Read rawenv.toml from cwd
    const toml_content = blk: {
        const fd = std.posix.openat(std.posix.AT.FDCWD, "rawenv.toml", .{}, 0) catch return null;
        defer _ = std.c.close(fd);
        var buf_list: std.ArrayList(u8) = .empty;
        errdefer buf_list.deinit(allocator);
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = std.posix.read(fd, &read_buf) catch return null;
            if (n == 0) break;
            buf_list.appendSlice(allocator, read_buf[0..n]) catch return null;
        }
        break :blk buf_list.toOwnedSlice(allocator) catch return null;
    };
    defer allocator.free(toml_content);

    const toml_services = parseToml(allocator, toml_content) catch return null;
    defer allocator.free(toml_services);
    if (toml_services.len == 0) return null;

    var services: std.ArrayList(app.Service) = .empty;
    for (toml_services) |ts| {
        const full_ver = resolveVersion(ts.name, ts.version);
        const installed = isInstalled(home, ts.name, full_ver);
        const active = isActive(home, ts.name);

        var pid: []const u8 = "—";
        var cpu: []const u8 = "—";
        var mem: []const u8 = "—";
        const status: []const u8 = if (active) blk: {
            // Try to get process stats
            if (getPid(allocator, ts.name)) |p| {
                pid = p;
                if (getPsStats(allocator, p)) |stats| {
                    cpu = std.fmt.allocPrint(allocator, "{s}%", .{stats.cpu}) catch "—";
                    mem = stats.mem;
                }
            }
            break :blk "running";
        } else if (installed) "stopped" else "not installed";

        services.append(allocator, .{
            .name = allocator.dupe(u8, ts.name) catch continue,
            .version = allocator.dupe(u8, full_ver) catch continue,
            .port = "—",
            .pid = pid,
            .cpu = cpu,
            .mem = mem,
            .uptime = "—",
            .status = status,
        }) catch continue;
    }

    return services.toOwnedSlice(allocator) catch null;
}

/// Load real log entries from ~/.rawenv/data/{service}/logs/
pub fn loadLogs(allocator: std.mem.Allocator, service_name: []const u8) ?[]app.LogEntry {
    if (comptime builtin.os.tag == .windows) return null;
    const home = std.mem.sliceTo(std.c.getenv("HOME") orelse return null, 0);
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/.rawenv/data/{s}/logs/current.log", .{ home, service_name }) catch return null;
    return readLogTail(allocator, path, 20);
}

/// Well-known port mappings
fn defaultPort(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "postgres")) return "5432";
    if (std.mem.eql(u8, name, "redis")) return "6379";
    if (std.mem.eql(u8, name, "node")) return "3000";
    if (std.mem.eql(u8, name, "mysql")) return "3306";
    if (std.mem.eql(u8, name, "meilisearch")) return "7700";
    if (std.mem.eql(u8, name, "mongodb")) return "27017";
    return "—";
}

/// Load services with port info filled in
pub fn loadServicesWithPorts(allocator: std.mem.Allocator) ?[]app.Service {
    const services = loadServices(allocator) orelse return null;
    for (services) |*svc| {
        if (std.mem.eql(u8, svc.port, "—")) {
            svc.port = defaultPort(svc.name);
        }
    }
    return services;
}

test "parseToml basic" {
    const input =
        \\name = "test"
        \\[services.node]
        \\version = "22"
        \\[services.redis]
        \\version = "7"
    ;
    const result = try parseToml(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("node", result[0].name);
    try std.testing.expectEqualStrings("22", result[0].version);
    try std.testing.expectEqualStrings("redis", result[1].name);
    try std.testing.expectEqualStrings("7", result[1].version);
}

test "parseToml empty" {
    const result = try parseToml(std.testing.allocator, "");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}
