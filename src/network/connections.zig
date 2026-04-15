const std = @import("std");

pub const Connection = struct {
    name: []const u8,
    url: []const u8,
    scheme: []const u8,
    host: []const u8,
    port: ?u16,
    remote: bool,
    suggestion: ?[]const u8,
};

const known_vars = [_][]const u8{
    "DATABASE_URL",
    "REDIS_URL",
    "MONGO_URL",
    "MONGODB_URI",
    "MYSQL_URL",
    "AMQP_URL",
    "RABBITMQ_URL",
    "ELASTICSEARCH_URL",
    "MEMCACHED_URL",
    "POSTGRES_URL",
};

const local_hosts = [_][]const u8{
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    "[::1]",
};

pub fn isRemote(url: []const u8) bool {
    const host = extractHost(url) orelse return false;
    for (&local_hosts) |lh| {
        if (std.ascii.eqlIgnoreCase(host, lh)) return false;
    }
    return true;
}

fn extractHost(url: []const u8) ?[]const u8 {
    const after_scheme = if (std.mem.indexOf(u8, url, "://")) |i| url[i + 3 ..] else return null;
    const after_user = if (std.mem.indexOfScalar(u8, after_scheme, '@')) |i| after_scheme[i + 1 ..] else after_scheme;
    const end = for (after_user, 0..) |c, i| {
        if (c == ':' or c == '/' or c == '?') break i;
    } else after_user.len;
    return if (end > 0) after_user[0..end] else null;
}

fn extractScheme(url: []const u8) ?[]const u8 {
    const i = std.mem.indexOf(u8, url, "://") orelse return null;
    return url[0..i];
}

fn suggestLocal(name: []const u8) ?[]const u8 {
    if (containsIgnoreCase(name, "postgres") or containsIgnoreCase(name, "database"))
        return "Use `rawenv add postgresql` for a local instance";
    if (containsIgnoreCase(name, "redis"))
        return "Use `rawenv add redis` for a local instance";
    if (containsIgnoreCase(name, "mongo"))
        return "Use `rawenv add mongodb` for a local instance";
    if (containsIgnoreCase(name, "mysql"))
        return "Use `rawenv add mysql` for a local instance";
    if (containsIgnoreCase(name, "rabbit") or containsIgnoreCase(name, "amqp"))
        return "Use `rawenv add rabbitmq` for a local instance";
    if (containsIgnoreCase(name, "elastic"))
        return "Use `rawenv add elasticsearch` for a local instance";
    return null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

/// Parse a .env file and detect connection URLs.
pub fn detectConnections(allocator: std.mem.Allocator, env_content: []const u8) ![]Connection {
    var results: std.ArrayList(Connection) = .empty;
    errdefer results.deinit(allocator);

    var it = std.mem.splitScalar(u8, env_content, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (line.len == 0 or line[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = std.mem.trim(u8, line[0..eq], &std.ascii.whitespace);
        var val = std.mem.trim(u8, line[eq + 1 ..], &std.ascii.whitespace);
        if (val.len >= 2 and (val[0] == '"' or val[0] == '\'') and val[val.len - 1] == val[0])
            val = val[1 .. val.len - 1];

        var is_known = false;
        for (&known_vars) |kv| {
            if (std.ascii.eqlIgnoreCase(name, kv)) {
                is_known = true;
                break;
            }
        }
        if (!is_known) continue;

        const remote = isRemote(val);
        try results.append(allocator, .{
            .name = name,
            .url = val,
            .scheme = extractScheme(val) orelse "",
            .host = extractHost(val) orelse "",
            .port = null,
            .remote = remote,
            .suggestion = if (remote) suggestLocal(name) else null,
        });
    }
    return results.toOwnedSlice(allocator);
}
