const std = @import("std");

pub const DetectionResult = struct {
    runtimes: []Entry,
    services: []Entry,

    pub const Entry = struct { key: []const u8, value: []const u8 };

    pub fn deinit(self: *DetectionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.runtimes);
        allocator.free(self.services);
        self.* = .{ .runtimes = &.{}, .services = &.{} };
    }
};

pub fn detect(allocator: std.mem.Allocator, dir: std.Io.Dir) !DetectionResult {
    var runtimes: std.ArrayList(DetectionResult.Entry) = .empty;
    errdefer runtimes.deinit(allocator);
    var services: std.ArrayList(DetectionResult.Entry) = .empty;
    errdefer services.deinit(allocator);

    if (readFile(allocator, dir, "package.json")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{
            .key = "node",
            .value = parseNodeVersion(allocator, data) orelse "22",
        });
    }

    if (readFile(allocator, dir, "composer.json")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{
            .key = "php",
            .value = parsePhpVersion(allocator, data) orelse "8.4",
        });
    }

    if (readFile(allocator, dir, ".env")) |data| {
        defer allocator.free(data);
        parseEnvServices(allocator, data, &services) catch {};
    }

    if (readFile(allocator, dir, "Cargo.toml")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{ .key = "rust", .value = "stable" });
    }

    if (readFile(allocator, dir, "go.mod")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{ .key = "go", .value = "1.22" });
    }

    if (readFile(allocator, dir, "requirements.txt")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{ .key = "python", .value = "3.12" });
    }

    if (readFile(allocator, dir, "Gemfile")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{ .key = "ruby", .value = "3.3" });
    }

    if (readFile(allocator, dir, "docker-compose.yml")) |data| {
        defer allocator.free(data);
        parseDockerComposeServices(allocator, data, &services) catch {};
    }

    return .{
        .runtimes = try runtimes.toOwnedSlice(allocator),
        .services = try services.toOwnedSlice(allocator),
    };
}

fn readFile(allocator: std.mem.Allocator, dir: std.Io.Dir, name: []const u8) ?[]const u8 {
    if (comptime @import("builtin").os.tag == .windows) {
        // Windows: use C fopen
        var path_buf: [512]u8 = undefined;
        const z = std.fmt.bufPrintZ(&path_buf, "{s}", .{name}) catch return null;
        const f = std.c.fopen(z, "rb") orelse return null;
        defer _ = std.c.fclose(f);
        var buf_list: std.ArrayList(u8) = .empty;
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = std.c.fread(&read_buf, 1, read_buf.len, f);
            if (n == 0) break;
            buf_list.appendSlice(allocator, read_buf[0..n]) catch return null;
        }
        return buf_list.toOwnedSlice(allocator) catch null;
    }
    const fd = std.posix.openat(dir.handle, name, .{}, 0) catch return null;
    defer _ = std.c.close(fd);
    var buf_list: std.ArrayList(u8) = .empty;
    errdefer buf_list.deinit(allocator);
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &read_buf) catch return null;
        if (n == 0) break;
        buf_list.appendSlice(allocator, read_buf[0..n]) catch return null;
    }
    return buf_list.toOwnedSlice(allocator) catch null;
}

fn parseNodeVersion(allocator: std.mem.Allocator, data: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return null;
    defer parsed.deinit();
    const engines = parsed.value.object.get("engines") orelse return null;
    const node_str = switch (engines.object.get("node") orelse return null) {
        .string => |s| s,
        else => return null,
    };
    // node_str points into parsed arena or input; extract and return a comptime-known version
    return matchMajor(node_str);
}

fn parsePhpVersion(allocator: std.mem.Allocator, data: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return null;
    defer parsed.deinit();
    const require = parsed.value.object.get("require") orelse return null;
    const php_str = switch (require.object.get("php") orelse return null) {
        .string => |s| s,
        else => return null,
    };
    return matchMajorMinor(php_str);
}

/// Map a version constraint string to a static version literal.
fn matchMajor(raw: []const u8) ?[]const u8 {
    const known = [_][]const u8{ "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "24" };
    var i: usize = 0;
    while (i < raw.len and !std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (i >= raw.len) return null;
    const start = i;
    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    const num = raw[start..i];
    for (known) |m| {
        if (std.mem.eql(u8, num, m)) return m;
    }
    return null;
}

/// Map a version constraint to a static "major.minor" literal.
fn matchMajorMinor(raw: []const u8) ?[]const u8 {
    const versions = [_][]const u8{ "7.4", "8.0", "8.1", "8.2", "8.3", "8.4" };
    var i: usize = 0;
    while (i < raw.len and !std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (i >= raw.len) return null;
    const start = i;
    while (i < raw.len and (std.ascii.isDigit(raw[i]) or raw[i] == '.')) : (i += 1) {}
    var ver = raw[start..i];
    if (ver.len > 0 and ver[ver.len - 1] == '.') ver = ver[0 .. ver.len - 1];
    for (versions) |v| {
        if (std.mem.eql(u8, ver, v)) return v;
    }
    return null;
}

fn parseEnvServices(allocator: std.mem.Allocator, data: []const u8, services: *std.ArrayList(DetectionResult.Entry)) !void {
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.startsWith(u8, trimmed, "DATABASE_URL=")) {
            const val = trimmed["DATABASE_URL=".len..];
            if (std.mem.indexOf(u8, val, "postgres") != null) {
                if (!hasService(services, "postgresql"))
                    try services.append(allocator, .{ .key = "postgresql", .value = "16" });
            } else if (std.mem.indexOf(u8, val, "mysql") != null) {
                if (!hasService(services, "mysql"))
                    try services.append(allocator, .{ .key = "mysql", .value = "8" });
            }
        } else if (std.mem.startsWith(u8, trimmed, "REDIS_URL=") or std.mem.startsWith(u8, trimmed, "REDIS_HOST=")) {
            if (!hasService(services, "redis"))
                try services.append(allocator, .{ .key = "redis", .value = "7" });
        }
    }
}

fn parseDockerComposeServices(allocator: std.mem.Allocator, data: []const u8, services: *std.ArrayList(DetectionResult.Entry)) !void {
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (!std.mem.startsWith(u8, trimmed, "image:")) continue;
        // Unwrap single-quoted, double-quoted, or unquoted image values
        // identically (e.g. Laravel Sail uses `image: 'mysql:8.0.39'`).
        const image = extractImageValue(trimmed["image:".len..]);
        if (image.len == 0) continue;
        // Match against the registry/org-stripped basename for the common
        // images, and a substring match for vendor images that always carry an
        // org prefix (e.g. `mcr.microsoft.com/azure-sql-edge`,
        // `getmeili/meilisearch`).
        const base = imageBasename(image);
        const Info = struct { key: []const u8, default: []const u8 };
        const info: ?Info = if (std.mem.startsWith(u8, base, "postgres"))
            .{ .key = "postgresql", .default = "16" }
        else if (std.mem.startsWith(u8, base, "redis"))
            .{ .key = "redis", .default = "7" }
        else if (std.mem.startsWith(u8, base, "mysql"))
            .{ .key = "mysql", .default = "8" }
        else if (std.mem.startsWith(u8, base, "mariadb"))
            .{ .key = "mariadb", .default = "11" }
        else if (std.mem.startsWith(u8, base, "mongo"))
            .{ .key = "mongodb", .default = "7" }
        else if (std.mem.indexOf(u8, image, "azure-sql-edge") != null or std.mem.indexOf(u8, image, "mssql") != null)
            .{ .key = "mssql", .default = "2022" }
        else if (std.mem.indexOf(u8, image, "meilisearch") != null)
            .{ .key = "meilisearch", .default = "1" }
        else
            null;
        if (info) |si| {
            if (!hasService(services, si.key)) {
                const ver = blk: {
                    const colon = std.mem.indexOfScalar(u8, base, ':') orelse break :blk si.default;
                    break :blk matchMajor(base[colon..]) orelse si.default;
                };
                try services.append(allocator, .{ .key = si.key, .value = ver });
            }
        }
    }
}

/// Extract the bare image reference from a compose `image:` value, treating
/// single-quoted, double-quoted, and unquoted forms identically. Trailing
/// inline comments on unquoted values are stripped.
fn extractImageValue(raw: []const u8) []const u8 {
    const s = std.mem.trim(u8, raw, &std.ascii.whitespace);
    if (s.len == 0) return s;
    if (s[0] == '\'' or s[0] == '"') {
        const q = s[0];
        const end = std.mem.indexOfScalarPos(u8, s, 1, q) orelse return s[1..];
        return s[1..end];
    }
    // Unquoted: drop an inline " # comment" suffix.
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        if (s[i] == '#' and (s[i - 1] == ' ' or s[i - 1] == '\t')) {
            return std.mem.trim(u8, s[0..i], &std.ascii.whitespace);
        }
    }
    return s;
}

/// Strip registry/org prefix → bare image name with tag retained.
/// "mcr.microsoft.com/azure-sql-edge" → "azure-sql-edge",
/// "getmeili/meilisearch:v1.6" → "meilisearch:v1.6".
fn imageBasename(image: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, image, '/');
    return if (slash) |s| image[s + 1 ..] else image;
}

fn hasService(services: *const std.ArrayList(DetectionResult.Entry), key: []const u8) bool {
    for (services.items) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return true;
    }
    return false;
}
