//! docker-compose.yml → rawenv.toml importer.
//!
//! Parses the common subset of the Compose file format and emits an equivalent
//! `rawenv.toml`. Recognised database/runtime images are mapped to rawenv
//! packages (e.g. `postgres:16` → `[services.postgres]` with `version = "16"`).
//! Port mappings, environment variables and `depends_on` edges are preserved.
//! Features rawenv cannot represent natively (custom Dockerfiles, networks,
//! volumes, unknown images) are reported as warnings instead of failing.
//!
//! The parser is intentionally a focused, line-oriented YAML reader rather than
//! a general YAML engine: Compose files have a predictable two/three-level
//! structure (`services:` → `<name>:` → property → nested value) which is all
//! we need to handle here. No external dependencies, no allocations leak — all
//! intermediate state lives in an internal arena and only the returned strings
//! are allocated with the caller's allocator.

const std = @import("std");

pub const ImportError = error{
    /// The file did not contain a recognisable `services:` block.
    NoServices,
} || std.mem.Allocator.Error;

/// Result of importing a compose file. Owns its strings; call `deinit`.
pub const ImportResult = struct {
    /// Generated rawenv.toml text.
    toml: []const u8,
    /// Human-readable warnings about features that could not be translated.
    warnings: []const []const u8,
    /// Number of services successfully mapped to rawenv packages.
    mapped_count: usize,

    pub fn deinit(self: *ImportResult, allocator: std.mem.Allocator) void {
        allocator.free(self.toml);
        for (self.warnings) |w| allocator.free(w);
        allocator.free(self.warnings);
        self.* = .{ .toml = &.{}, .warnings = &.{}, .mapped_count = 0 };
    }
};

const EnvVar = struct { name: []const u8, value: []const u8 };

const ComposeService = struct {
    name: []const u8,
    image: ?[]const u8 = null,
    has_build: bool = false,
    ports: std.ArrayList([]const u8) = .empty,
    env: std.ArrayList(EnvVar) = .empty,
    depends_on: std.ArrayList([]const u8) = .empty,
    has_volumes: bool = false,
    // Resolved during mapping:
    pkg: ?[]const u8 = null, // rawenv package name (null = unmappable)
    version: []const u8 = "",
    section_key: []const u8 = "", // final [services.<key>] name
    port: u16 = 0,
};

/// (image-basename prefix, rawenv package, default version) mapping table.
const ImageMap = struct { prefix: []const u8, pkg: []const u8, default_version: []const u8 };
const image_table = [_]ImageMap{
    .{ .prefix = "postgres", .pkg = "postgres", .default_version = "16" },
    .{ .prefix = "postgresql", .pkg = "postgres", .default_version = "16" },
    .{ .prefix = "redis", .pkg = "redis", .default_version = "7" },
    .{ .prefix = "valkey", .pkg = "redis", .default_version = "7" },
    .{ .prefix = "node", .pkg = "node", .default_version = "22" },
    .{ .prefix = "python", .pkg = "python", .default_version = "3.12" },
    .{ .prefix = "php", .pkg = "php", .default_version = "8.3" },
    .{ .prefix = "mysql", .pkg = "mysql", .default_version = "8" },
    .{ .prefix = "mariadb", .pkg = "mariadb", .default_version = "11" },
    .{ .prefix = "mongo", .pkg = "mongodb", .default_version = "7" },
    .{ .prefix = "mongodb", .pkg = "mongodb", .default_version = "7" },
    .{ .prefix = "meilisearch", .pkg = "meilisearch", .default_version = "1" },
};

/// Import a compose document and produce an equivalent rawenv.toml.
///
/// `project_name` is written verbatim as the top-level `name`. Strings in the
/// returned `ImportResult` are owned by `allocator` (free with `deinit`).
pub fn importCompose(
    allocator: std.mem.Allocator,
    compose_yaml: []const u8,
    project_name: []const u8,
) ImportError!ImportResult {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var services: std.ArrayList(ComposeService) = .empty;
    var warnings: std.ArrayList([]const u8) = .empty;

    try parse(arena, compose_yaml, &services, &warnings);

    if (services.items.len == 0) return ImportError.NoServices;

    // Map images to rawenv packages and assign unique section keys.
    var used_keys: std.ArrayList([]const u8) = .empty;
    var mapped_count: usize = 0;
    for (services.items) |*svc| {
        if (svc.has_build and svc.image == null) {
            try warnings.append(arena, try std.fmt.allocPrint(
                arena,
                "service '{s}': custom build (Dockerfile) is not supported by rawenv — skipped",
                .{svc.name},
            ));
            continue;
        }
        const image = svc.image orelse {
            try warnings.append(arena, try std.fmt.allocPrint(
                arena,
                "service '{s}': no image specified — skipped",
                .{svc.name},
            ));
            continue;
        };
        const mapping = mapImage(image) orelse {
            try warnings.append(arena, try std.fmt.allocPrint(
                arena,
                "service '{s}': image '{s}' has no rawenv equivalent — skipped",
                .{ svc.name, image },
            ));
            continue;
        };
        svc.pkg = mapping.pkg;
        svc.version = extractVersion(image) orelse mapping.default_version;
        svc.port = firstHostPort(svc.ports.items);
        svc.section_key = try uniqueKey(arena, &used_keys, mapping.pkg, svc.name);
        try used_keys.append(arena, svc.section_key);
        mapped_count += 1;

        if (svc.has_volumes) {
            try warnings.append(arena, try std.fmt.allocPrint(
                arena,
                "service '{s}': volumes are not managed by rawenv — ignored",
                .{svc.name},
            ));
        }
    }

    const toml = try generate(arena, project_name, services.items);

    // Copy results into the caller's allocator so the arena can be freed.
    const toml_out = try allocator.dupe(u8, toml);
    errdefer allocator.free(toml_out);

    const warns_out = try allocator.alloc([]const u8, warnings.items.len);
    var filled: usize = 0;
    errdefer {
        for (warns_out[0..filled]) |w| allocator.free(w);
        allocator.free(warns_out);
    }
    for (warnings.items, 0..) |w, idx| {
        warns_out[idx] = try allocator.dupe(u8, w);
        filled = idx + 1;
    }

    return .{ .toml = toml_out, .warnings = warns_out, .mapped_count = mapped_count };
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

const Prop = enum { none, ports, environment, depends_on, volumes };

fn parse(
    arena: std.mem.Allocator,
    data: []const u8,
    services: *std.ArrayList(ComposeService),
    warnings: *std.ArrayList([]const u8),
) ImportError!void {
    var in_services = false;
    var service_indent: ?usize = null;
    var prop_indent: ?usize = null;
    var cur: ?*ComposeService = null;
    var cur_prop: Prop = .none;
    var warned_networks = false;
    var warned_top_volumes = false;

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = stripCr(raw);
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const indent = leadingSpaces(line);

        if (indent == 0) {
            const key = keyOf(trimmed);
            if (std.mem.eql(u8, key, "services")) {
                in_services = true;
                service_indent = null;
                cur = null;
                cur_prop = .none;
                continue;
            }
            in_services = false;
            cur = null;
            if (std.mem.eql(u8, key, "networks") and !warned_networks) {
                warned_networks = true;
                try warnings.append(arena, try arena.dupe(u8, "top-level 'networks' is not supported by rawenv — ignored"));
            } else if (std.mem.eql(u8, key, "volumes") and !warned_top_volumes) {
                warned_top_volumes = true;
                try warnings.append(arena, try arena.dupe(u8, "top-level named 'volumes' are not managed by rawenv — ignored"));
            } else if (std.mem.eql(u8, key, "secrets") or std.mem.eql(u8, key, "configs")) {
                try warnings.append(arena, try std.fmt.allocPrint(arena, "top-level '{s}' is not supported by rawenv — ignored", .{key}));
            }
            continue;
        }

        if (!in_services) continue;

        if (service_indent == null) service_indent = indent;
        const svc_indent = service_indent.?;

        if (indent < svc_indent) continue; // dedent out of services block content

        if (indent == svc_indent) {
            // New service declaration: "<name>:".
            const name = keyOf(trimmed);
            try services.append(arena, .{ .name = try arena.dupe(u8, name) });
            cur = &services.items[services.items.len - 1];
            prop_indent = null;
            cur_prop = .none;
            continue;
        }

        // indent > svc_indent → property of, or nested value within, current service.
        const svc = cur orelse continue;

        if (std.mem.startsWith(u8, trimmed, "- ") or std.mem.eql(u8, trimmed, "-")) {
            const item = std.mem.trim(u8, trimmed[1..], &std.ascii.whitespace);
            try appendListItem(arena, svc, cur_prop, item);
            continue;
        }

        if (prop_indent == null) prop_indent = indent;

        if (indent <= prop_indent.?) {
            // A property key line: "key:" or "key: value".
            const key = keyOf(trimmed);
            const value = valueOf(trimmed);
            cur_prop = .none;
            if (std.mem.eql(u8, key, "image")) {
                if (value.len > 0) svc.image = try arena.dupe(u8, unquote(value));
            } else if (std.mem.eql(u8, key, "build")) {
                svc.has_build = true;
            } else if (std.mem.eql(u8, key, "ports")) {
                cur_prop = .ports;
                if (value.len > 0) try appendListItem(arena, svc, .ports, value);
            } else if (std.mem.eql(u8, key, "environment")) {
                cur_prop = .environment;
                if (value.len > 0) try appendListItem(arena, svc, .environment, value);
            } else if (std.mem.eql(u8, key, "depends_on")) {
                cur_prop = .depends_on;
                if (value.len > 0) try appendListItem(arena, svc, .depends_on, value);
            } else if (std.mem.eql(u8, key, "volumes")) {
                cur_prop = .volumes;
                svc.has_volumes = true;
            }
        } else {
            // Deeper nested entry: env map entry or depends_on long-form key.
            switch (cur_prop) {
                .environment => {
                    const k = keyOf(trimmed);
                    const v = valueOf(trimmed);
                    try svc.env.append(arena, .{ .name = try arena.dupe(u8, k), .value = try arena.dupe(u8, unquote(v)) });
                },
                .depends_on => {
                    // Long form: "service:\n  condition: ...". Capture the service key.
                    if (std.mem.endsWith(u8, trimmed, ":")) {
                        const name = keyOf(trimmed);
                        try svc.depends_on.append(arena, try arena.dupe(u8, name));
                    }
                },
                .volumes => svc.has_volumes = true,
                else => {},
            }
        }
    }
}

fn appendListItem(arena: std.mem.Allocator, svc: *ComposeService, prop: Prop, item_raw: []const u8) ImportError!void {
    const item = stripInlineComment(item_raw);
    switch (prop) {
        .ports => try svc.ports.append(arena, try arena.dupe(u8, unquote(item))),
        .depends_on => try svc.depends_on.append(arena, try arena.dupe(u8, unquote(item))),
        .volumes => svc.has_volumes = true,
        .environment => {
            // List form: "KEY=value".
            const unq = unquote(item);
            const eq = std.mem.indexOfScalar(u8, unq, '=') orelse {
                try svc.env.append(arena, .{ .name = try arena.dupe(u8, unq), .value = "" });
                return;
            };
            const name = std.mem.trim(u8, unq[0..eq], &std.ascii.whitespace);
            const value = std.mem.trim(u8, unq[eq + 1 ..], &std.ascii.whitespace);
            try svc.env.append(arena, .{
                .name = try arena.dupe(u8, name),
                .value = try arena.dupe(u8, unquote(value)),
            });
        },
        .none => {},
    }
}

// ---------------------------------------------------------------------------
// Image / version mapping
// ---------------------------------------------------------------------------

fn mapImage(image: []const u8) ?ImageMap {
    const short = imageBasename(image);
    for (image_table) |entry| {
        if (std.mem.startsWith(u8, short, entry.prefix)) {
            // Guard against e.g. "postgresql" matching "postgres" wrongly is fine
            // (both map to postgres), but ensure the next char is a tag/end so
            // "nodejs" doesn't match "node" by accident.
            const plen = entry.prefix.len;
            if (short.len == plen or short[plen] == ':') return entry;
        }
    }
    return null;
}

/// Strip registry/org prefix and tag → bare image name with tag retained.
/// "docker.io/library/postgres:16-alpine" → "postgres:16-alpine".
fn imageBasename(image: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, image, '/');
    return if (slash) |s| image[s + 1 ..] else image;
}

/// Extract a clean version token from an image tag.
/// "postgres:16-alpine" → "16", "python:3.12-slim" → "3.12", "redis:latest" → null.
fn extractVersion(image: []const u8) ?[]const u8 {
    const short = imageBasename(image);
    const colon = std.mem.indexOfScalar(u8, short, ':') orelse return null;
    const tag = short[colon + 1 ..];
    if (tag.len == 0) return null;
    // Take the leading [0-9.] run; stop at the first non-version character.
    var end: usize = 0;
    while (end < tag.len and (std.ascii.isDigit(tag[end]) or tag[end] == '.')) : (end += 1) {}
    if (end == 0) return null; // tag like "latest", "bookworm"
    var ver = tag[0..end];
    // Trim a trailing dot, e.g. "16." → "16".
    if (ver.len > 0 and ver[ver.len - 1] == '.') ver = ver[0 .. ver.len - 1];
    if (ver.len == 0) return null;
    return ver;
}

/// Pick the published (host) port from a list of compose port mappings.
fn firstHostPort(ports: []const []const u8) u16 {
    for (ports) |p| {
        if (parseHostPort(p)) |port| return port;
    }
    return 0;
}

/// "5432:5432" → 5432, "127.0.0.1:8080:80" → 8080, "6379" → 6379,
/// "3000:3000/tcp" → 3000.
fn parseHostPort(spec_raw: []const u8) ?u16 {
    var spec = std.mem.trim(u8, spec_raw, &std.ascii.whitespace);
    // Drop protocol suffix.
    if (std.mem.indexOfScalar(u8, spec, '/')) |slash| spec = spec[0..slash];
    if (spec.len == 0) return null;

    var segs: [3][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, spec, ':');
    while (it.next()) |seg| {
        if (n < segs.len) {
            segs[n] = seg;
        }
        n += 1;
    }
    const host_seg: []const u8 = switch (n) {
        1 => segs[0], // "6379" — container port, used as the listen port
        2 => segs[0], // "host:container" — published host port
        else => if (n >= 3) segs[1] else return null, // "ip:host:container"
    };
    const t = std.mem.trim(u8, host_seg, &std.ascii.whitespace);
    return std.fmt.parseInt(u16, t, 10) catch null;
}

/// Build a `[services.<key>]` name that is unique within the file. Prefers the
/// bare package name; on collision falls back to "<pkg>.<compose-name>".
fn uniqueKey(
    arena: std.mem.Allocator,
    used: *std.ArrayList([]const u8),
    pkg: []const u8,
    compose_name: []const u8,
) ImportError![]const u8 {
    if (!containsStr(used.items, pkg)) return pkg;
    const combined = try std.fmt.allocPrint(arena, "{s}.{s}", .{ pkg, compose_name });
    if (!containsStr(used.items, combined)) return combined;
    // Extremely unlikely: append an index.
    var i: usize = 2;
    while (true) : (i += 1) {
        const c = try std.fmt.allocPrint(arena, "{s}.{s}{d}", .{ pkg, compose_name, i });
        if (!containsStr(used.items, c)) return c;
    }
}

// ---------------------------------------------------------------------------
// TOML generation
// ---------------------------------------------------------------------------

fn generate(arena: std.mem.Allocator, project_name: []const u8, services: []const ComposeService) ImportError![]const u8 {
    var buf: std.ArrayList(u8) = .empty;

    try buf.appendSlice(arena, "name = \"");
    try buf.appendSlice(arena, project_name);
    try buf.appendSlice(arena, "\"\nversion = \"1\"\n");

    for (services) |svc| {
        if (svc.pkg == null) continue; // unmapped — skipped (warned earlier)

        try buf.print(arena, "\n[services.{s}]\n", .{svc.section_key});
        try buf.print(arena, "version = \"{s}\"\n", .{svc.version});
        if (svc.port != 0) try buf.print(arena, "port = {d}\n", .{svc.port});

        if (svc.depends_on.items.len > 0) {
            try buf.appendSlice(arena, "depends_on = [");
            var wrote = false;
            for (svc.depends_on.items) |dep| {
                const dep_key = resolveDep(services, dep) orelse continue;
                if (wrote) try buf.appendSlice(arena, ", ");
                try buf.print(arena, "\"{s}\"", .{dep_key});
                wrote = true;
            }
            try buf.appendSlice(arena, "]\n");
        }

        if (svc.env.items.len > 0) {
            try buf.print(arena, "\n[services.{s}.env]\n", .{svc.section_key});
            for (svc.env.items) |e| {
                try buf.print(arena, "{s} = \"{s}\"\n", .{ e.name, escapeQuotes(arena, e.value) catch e.value });
            }
        }
    }

    return try buf.toOwnedSlice(arena);
}

/// Resolve a compose `depends_on` target (a compose service name) to the final
/// rawenv section key, so dependency edges survive the renaming to package names.
fn resolveDep(services: []const ComposeService, compose_name: []const u8) ?[]const u8 {
    for (services) |svc| {
        if (svc.pkg == null) continue;
        if (std.mem.eql(u8, svc.name, compose_name)) return svc.section_key;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Small string helpers
// ---------------------------------------------------------------------------

fn stripCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn leadingSpaces(line: []const u8) usize {
    var n: usize = 0;
    while (n < line.len and (line[n] == ' ' or line[n] == '\t')) : (n += 1) {}
    return n;
}

/// The key part of "key: value" (or "key:" / "name:") — text before the first ':'.
fn keyOf(trimmed: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return trimmed;
    return std.mem.trim(u8, trimmed[0..colon], &std.ascii.whitespace);
}

/// The value part of "key: value" — text after the first ':' (may be empty),
/// with any trailing inline comment removed.
fn valueOf(trimmed: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return "";
    return stripInlineComment(std.mem.trim(u8, trimmed[colon + 1 ..], &std.ascii.whitespace));
}

/// Remove an unquoted trailing " # comment". Conservative: only strips when the
/// '#' is preceded by whitespace and the value is not quoted.
fn stripInlineComment(s: []const u8) []const u8 {
    if (s.len == 0) return s;
    if (s[0] == '"' or s[0] == '\'') return s; // quoted — leave intact
    var i: usize = 1;
    while (i < s.len) : (i += 1) {
        if (s[i] == '#' and (s[i - 1] == ' ' or s[i - 1] == '\t')) {
            return std.mem.trim(u8, s[0..i], &std.ascii.whitespace);
        }
    }
    return s;
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and ((s[0] == '"' and s[s.len - 1] == '"') or (s[0] == '\'' and s[s.len - 1] == '\''))) {
        return s[1 .. s.len - 1];
    }
    return s;
}

fn escapeQuotes(arena: std.mem.Allocator, s: []const u8) ImportError![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '"') == null and std.mem.indexOfScalar(u8, s, '\\') == null) return s;
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (c == '"' or c == '\\') try out.append(arena, '\\');
        try out.append(arena, c);
    }
    return try out.toOwnedSlice(arena);
}

fn containsStr(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |h| if (std.mem.eql(u8, h, needle)) return true;
    return false;
}
