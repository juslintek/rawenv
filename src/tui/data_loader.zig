const std = @import("std");
const builtin = @import("builtin");
const app = @import("app.zig");

/// Aggregate data struct returned by loaders
pub const TuiData = struct {
    services: []app.Service,
    logs: []app.LogEntry,
    stats: Stats,

    pub const Stats = struct {
        total_cpu: []const u8 = "—",
        total_mem: []const u8 = "—",
        total_disk: []const u8 = "—",
    };
};

/// Load data from rawenv.toml config at given path
pub fn loadFromConfig(allocator: std.mem.Allocator, config_path: []const u8) ?TuiData {
    const content = readFile(allocator, config_path) orelse return null;
    defer allocator.free(content);

    const toml_services = parseToml(allocator, content) catch return null;
    defer allocator.free(toml_services);
    if (toml_services.len == 0) return null;

    const home = getHome() orelse return null;
    var services: std.ArrayList(app.Service) = .empty;
    for (toml_services) |ts| {
        const full_ver = resolveVersion(ts.name, ts.version);
        const active = isActive(home, ts.name);
        const status: []const u8 = if (active) "running" else "stopped";
        services.append(allocator, .{
            .name = allocator.dupe(u8, ts.name) catch continue,
            .version = allocator.dupe(u8, full_ver) catch continue,
            .port = defaultPort(ts.name),
            .pid = "—",
            .cpu = "—",
            .mem = "—",
            .uptime = "—",
            .status = status,
        }) catch continue;
    }

    return .{
        .services = services.toOwnedSlice(allocator) catch return null,
        .logs = allocator.dupe(app.LogEntry, &app.default_logs) catch return null,
        .stats = .{},
    };
}

/// Load data from shared/mock-data.json for demo mode
pub fn loadFromMockData(allocator: std.mem.Allocator, json_path: []const u8) ?TuiData {
    const content = readFile(allocator, json_path) orelse return null;
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value.object;

    // Parse services
    var services: std.ArrayList(app.Service) = .empty;
    if (root.get("services")) |svcs_val| {
        for (svcs_val.array.items) |item| {
            const obj = item.object;
            services.append(allocator, .{
                .name = allocator.dupe(u8, obj.get("name").?.string) catch continue,
                .version = jsonStr(allocator, obj.get("version").?) catch continue,
                .port = jsonStr(allocator, obj.get("port").?) catch continue,
                .pid = jsonStrOrDash(allocator, obj.get("pid").?),
                .cpu = jsonStrOrDash(allocator, obj.get("cpu").?),
                .mem = jsonStrOrDash(allocator, obj.get("mem").?),
                .uptime = jsonStrOrDash(allocator, obj.get("uptime").?),
                .status = allocator.dupe(u8, obj.get("status").?.string) catch continue,
            }) catch continue;
        }
    }

    // Parse logs
    var logs: std.ArrayList(app.LogEntry) = .empty;
    if (root.get("logs")) |logs_val| {
        for (logs_val.array.items) |item| {
            const obj = item.object;
            logs.append(allocator, .{
                .time = allocator.dupe(u8, obj.get("time").?.string) catch continue,
                .level = allocator.dupe(u8, obj.get("level").?.string) catch continue,
                .msg = allocator.dupe(u8, obj.get("msg").?.string) catch continue,
            }) catch continue;
        }
    }

    return .{
        .services = services.toOwnedSlice(allocator) catch return null,
        .logs = logs.toOwnedSlice(allocator) catch return null,
        .stats = .{},
    };
}

fn jsonStr(allocator: std.mem.Allocator, val: std.json.Value) ![]const u8 {
    return switch (val) {
        .string => |s| try allocator.dupe(u8, s),
        .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(allocator, "{d:.1}", .{f}),
        .null => try allocator.dupe(u8, "—"),
        else => try allocator.dupe(u8, "—"),
    };
}

fn jsonStrOrDash(allocator: std.mem.Allocator, val: std.json.Value) []const u8 {
    return switch (val) {
        .string => |s| allocator.dupe(u8, s) catch "—",
        .integer => |i| std.fmt.allocPrint(allocator, "{d}", .{i}) catch "—",
        .null => allocator.dupe(u8, "—") catch "—",
        else => allocator.dupe(u8, "—") catch "—",
    };
}

// --- Existing functionality (kept for backward compat) ---

fn resolveVersion(name: []const u8, version: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "node")) {
        if (std.mem.eql(u8, version, "22")) return "22.15.0";
        if (std.mem.eql(u8, version, "20")) return "20.18.3";
        if (std.mem.eql(u8, version, "18")) return "18.20.8";
    }
    return version;
}

const TomlService = struct { name: []const u8, version: []const u8 };

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) ![]TomlService {
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

fn getHome() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) return null;
    return if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else null;
}

fn isActive(home: []const u8, name: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/.rawenv/bin/{s}", .{ home, name }) catch return false;
    return std.c.access(path, 0) == 0;
}

fn isInstalled(home: []const u8, name: []const u8, version: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/.rawenv/store/{s}-{s}", .{ home, name, version }) catch return false;
    return std.c.access(path, 0) == 0;
}

fn defaultPort(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "postgres")) return "5432";
    if (std.mem.eql(u8, name, "redis")) return "6379";
    if (std.mem.eql(u8, name, "node")) return "3000";
    if (std.mem.eql(u8, name, "mysql")) return "3306";
    if (std.mem.eql(u8, name, "meilisearch")) return "7700";
    if (std.mem.eql(u8, name, "mongodb")) return "27017";
    return "—";
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    const pathZ = allocator.dupeZ(u8, path) catch return null;
    defer allocator.free(pathZ);
    const fd = std.posix.openat(std.posix.AT.FDCWD, pathZ, .{}, 0) catch return null;
    defer _ = std.c.close(fd);
    var buf_list: std.ArrayList(u8) = .empty;
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &read_buf) catch {
            buf_list.deinit(allocator);
            return null;
        };
        if (n == 0) break;
        buf_list.appendSlice(allocator, read_buf[0..n]) catch {
            buf_list.deinit(allocator);
            return null;
        };
    }
    return buf_list.toOwnedSlice(allocator) catch null;
}

/// Load real services from rawenv.toml in cwd + filesystem status
pub fn loadServices(allocator: std.mem.Allocator) ?[]app.Service {
    if (comptime builtin.os.tag == .windows) return null;
    const data = loadFromConfig(allocator, "rawenv.toml") orelse return null;
    return data.services;
}

/// Load real log entries from ~/.rawenv/data/{service}/logs/
pub fn loadLogs(allocator: std.mem.Allocator, service_name: []const u8) ?[]app.LogEntry {
    if (comptime builtin.os.tag == .windows) return null;
    const home = getHome() orelse return null;
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/.rawenv/data/{s}/logs/current.log", .{ home, service_name }) catch return null;
    return readLogTail(allocator, path, 20);
}

fn readLogTail(allocator: std.mem.Allocator, path: []const u8, max_lines: usize) ?[]app.LogEntry {
    const content = readFile(allocator, path) orelse return null;
    defer allocator.free(content);

    var all_lines: std.ArrayList([]const u8) = .empty;
    defer all_lines.deinit(allocator);
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) all_lines.append(allocator, line) catch continue;
    }

    const start = if (all_lines.items.len > max_lines) all_lines.items.len - max_lines else 0;
    var entries: std.ArrayList(app.LogEntry) = .empty;
    for (all_lines.items[start..]) |line| {
        entries.append(allocator, .{
            .time = allocator.dupe(u8, if (line.len >= 8) line[0..8] else line) catch continue,
            .level = "normal",
            .msg = allocator.dupe(u8, line) catch continue,
        }) catch continue;
    }
    return entries.toOwnedSlice(allocator) catch null;
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

test "loadFromMockData parses json" {
    const data = loadFromMockData(std.testing.allocator, "shared/mock-data.json") orelse {
        // File may not be accessible from test cwd; skip
        return;
    };
    defer {
        for (data.services) |svc| {
            std.testing.allocator.free(svc.name);
            std.testing.allocator.free(svc.version);
            std.testing.allocator.free(svc.port);
            std.testing.allocator.free(svc.pid);
            std.testing.allocator.free(svc.cpu);
            std.testing.allocator.free(svc.mem);
            std.testing.allocator.free(svc.uptime);
            std.testing.allocator.free(svc.status);
        }
        std.testing.allocator.free(data.services);
        for (data.logs) |log| {
            std.testing.allocator.free(log.time);
            std.testing.allocator.free(log.level);
            std.testing.allocator.free(log.msg);
        }
        std.testing.allocator.free(data.logs);
    }
    try std.testing.expectEqual(@as(usize, 5), data.services.len);
    try std.testing.expectEqualStrings("PostgreSQL", data.services[0].name);
    try std.testing.expectEqual(@as(usize, 8), data.logs.len);
}
