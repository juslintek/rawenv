const std = @import("std");

// ─── Project Discovery ───────────────────────────────────────────────────────

pub const DiscoveredProject = struct {
    path: []const u8,
    has_rawenv_toml: bool,
    stack: []const u8,
};

const scan_dirs = [_][]const u8{ "", "Projects", "Developer", "src", "code" };
const manifest_files = [_]struct { name: []const u8, stack: []const u8 }{
    .{ .name = "rawenv.toml", .stack = "rawenv" },
    .{ .name = "package.json", .stack = "node" },
    .{ .name = "composer.json", .stack = "php" },
    .{ .name = "Cargo.toml", .stack = "rust" },
    .{ .name = "go.mod", .stack = "go" },
    .{ .name = "build.zig", .stack = "zig" },
    .{ .name = "Gemfile", .stack = "ruby" },
    .{ .name = "requirements.txt", .stack = "python" },
    .{ .name = "pyproject.toml", .stack = "python" },
};

pub fn discover(allocator: std.mem.Allocator) ![]DiscoveredProject {
    var results: std.ArrayList(DiscoveredProject) = .empty;
    errdefer {
        for (results.items) |p| allocator.free(p.path);
        results.deinit(allocator);
    }

    const home = if (std.c.getenv("HOME")) |s| std.mem.sliceTo(s, 0) else return results.toOwnedSlice(allocator);

    for (&scan_dirs) |sub| {
        const base = if (sub.len > 0)
            std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, sub }) catch continue
        else
            allocator.dupe(u8, home) catch continue;
        defer allocator.free(base);

        // TODO: openDirAbsolute needs Io in 0.16.0
        continue;
    }

    return results.toOwnedSlice(allocator);
}

pub fn freeResults(allocator: std.mem.Allocator, results: []DiscoveredProject) void {
    for (results) |p| allocator.free(p.path);
    allocator.free(results);
}

// ─── Service Extensions / Plugins ────────────────────────────────────────────

pub const Extension = struct {
    name: []const u8,
    version: []const u8,
    service: []const u8,
    install_command: []const u8,
    description: []const u8,
};

const ServiceType = enum { postgresql, redis, php, node };

fn classifyService(name: []const u8) ?ServiceType {
    if (std.mem.eql(u8, name, "postgresql") or std.mem.eql(u8, name, "postgres")) return .postgresql;
    if (std.mem.eql(u8, name, "redis")) return .redis;
    if (std.mem.eql(u8, name, "php")) return .php;
    if (std.mem.eql(u8, name, "node") or std.mem.eql(u8, name, "nodejs")) return .node;
    return null;
}

const pg_extensions = [_]Extension{
    .{ .name = "pgvector", .version = "0.7", .service = "postgresql", .install_command = "CREATE EXTENSION pgvector;", .description = "Vector similarity search" },
    .{ .name = "postgis", .version = "3.4", .service = "postgresql", .install_command = "CREATE EXTENSION postgis;", .description = "Geographic objects support" },
    .{ .name = "pg_stat_statements", .version = "1.10", .service = "postgresql", .install_command = "CREATE EXTENSION pg_stat_statements;", .description = "Query statistics tracking" },
    .{ .name = "timescaledb", .version = "2.14", .service = "postgresql", .install_command = "CREATE EXTENSION timescaledb;", .description = "Time-series data" },
};

const redis_extensions = [_]Extension{
    .{ .name = "redisearch", .version = "2.8", .service = "redis", .install_command = "loadmodule /path/to/redisearch.so", .description = "Full-text search" },
    .{ .name = "redisjson", .version = "2.6", .service = "redis", .install_command = "loadmodule /path/to/redisjson.so", .description = "JSON data type" },
    .{ .name = "redisbloom", .version = "2.6", .service = "redis", .install_command = "loadmodule /path/to/redisbloom.so", .description = "Probabilistic data structures" },
};

const php_extensions = [_]Extension{
    .{ .name = "redis", .version = "6.0", .service = "php", .install_command = "pecl install redis", .description = "Redis client extension" },
    .{ .name = "xdebug", .version = "3.3", .service = "php", .install_command = "pecl install xdebug", .description = "Debugger and profiler" },
    .{ .name = "imagick", .version = "3.7", .service = "php", .install_command = "pecl install imagick", .description = "ImageMagick bindings" },
    .{ .name = "opcache", .version = "8.3", .service = "php", .install_command = "pecl install opcache", .description = "Opcode cache" },
    .{ .name = "pdo_pgsql", .version = "8.3", .service = "php", .install_command = "pecl install pdo_pgsql", .description = "PostgreSQL PDO driver" },
};

const node_extensions = [_]Extension{
    .{ .name = "pm2", .version = "5.3", .service = "node", .install_command = "npm install -g pm2", .description = "Process manager" },
    .{ .name = "nodemon", .version = "3.1", .service = "node", .install_command = "npm install -g nodemon", .description = "Auto-restart on changes" },
    .{ .name = "typescript", .version = "5.4", .service = "node", .install_command = "npm install -g typescript", .description = "TypeScript compiler" },
    .{ .name = "eslint", .version = "9.0", .service = "node", .install_command = "npm install -g eslint", .description = "JavaScript linter" },
};

/// Returns available extensions for a given service name.
pub fn discoverExtensions(allocator: std.mem.Allocator, service_name: []const u8) ![]const Extension {
    _ = allocator;
    const svc = classifyService(service_name) orelse return &.{};
    return switch (svc) {
        .postgresql => &pg_extensions,
        .redis => &redis_extensions,
        .php => &php_extensions,
        .node => &node_extensions,
    };
}

/// Returns the install command string for a specific extension of a service.
pub fn installExtension(allocator: std.mem.Allocator, service_name: []const u8, ext_name: []const u8) ![]const u8 {
    const svc = classifyService(service_name) orelse return error.UnknownService;
    const registry: []const Extension = switch (svc) {
        .postgresql => &pg_extensions,
        .redis => &redis_extensions,
        .php => &php_extensions,
        .node => &node_extensions,
    };
    for (registry) |ext| {
        if (std.mem.eql(u8, ext.name, ext_name)) {
            return allocator.dupe(u8, ext.install_command);
        }
    }
    return error.UnknownExtension;
}

/// Returns installed extensions for a service (stub — returns empty).
pub fn listInstalledExtensions(allocator: std.mem.Allocator, service_name: []const u8) ![]const Extension {
    _ = allocator;
    _ = service_name;
    return &.{};
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "discover returns empty on missing HOME" {
    const allocator = std.testing.allocator;
    const results = try discover(allocator);
    freeResults(allocator, results);
}

test "discoverExtensions returns postgresql extensions" {
    const exts = try discoverExtensions(std.testing.allocator, "postgresql");
    try std.testing.expect(exts.len == 4);
    try std.testing.expectEqualStrings("pgvector", exts[0].name);
}

test "discoverExtensions returns redis extensions" {
    const exts = try discoverExtensions(std.testing.allocator, "redis");
    try std.testing.expect(exts.len == 3);
    try std.testing.expectEqualStrings("redisearch", exts[0].name);
}

test "discoverExtensions returns php extensions" {
    const exts = try discoverExtensions(std.testing.allocator, "php");
    try std.testing.expect(exts.len == 5);
}

test "discoverExtensions returns node extensions" {
    const exts = try discoverExtensions(std.testing.allocator, "node");
    try std.testing.expect(exts.len == 4);
    try std.testing.expectEqualStrings("pm2", exts[0].name);
}

test "discoverExtensions returns empty for unknown service" {
    const exts = try discoverExtensions(std.testing.allocator, "unknown");
    try std.testing.expect(exts.len == 0);
}

test "installExtension returns correct command for postgresql" {
    const cmd = try installExtension(std.testing.allocator, "postgresql", "pgvector");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("CREATE EXTENSION pgvector;", cmd);
}

test "installExtension returns correct command for node" {
    const cmd = try installExtension(std.testing.allocator, "node", "typescript");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("npm install -g typescript", cmd);
}

test "installExtension returns correct command for php" {
    const cmd = try installExtension(std.testing.allocator, "php", "xdebug");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("pecl install xdebug", cmd);
}

test "installExtension returns correct command for redis" {
    const cmd = try installExtension(std.testing.allocator, "redis", "redisjson");
    defer std.testing.allocator.free(cmd);
    try std.testing.expectEqualStrings("loadmodule /path/to/redisjson.so", cmd);
}

test "installExtension returns error for unknown extension" {
    const result = installExtension(std.testing.allocator, "postgresql", "nonexistent");
    try std.testing.expectError(error.UnknownExtension, result);
}

test "installExtension returns error for unknown service" {
    const result = installExtension(std.testing.allocator, "unknown", "anything");
    try std.testing.expectError(error.UnknownService, result);
}

test "listInstalledExtensions returns empty" {
    const exts = try listInstalledExtensions(std.testing.allocator, "postgresql");
    try std.testing.expect(exts.len == 0);
}

test "classifyService aliases" {
    // postgres alias
    const exts = try discoverExtensions(std.testing.allocator, "postgres");
    try std.testing.expect(exts.len == 4);
    // nodejs alias
    const node_exts = try discoverExtensions(std.testing.allocator, "nodejs");
    try std.testing.expect(node_exts.len == 4);
}
