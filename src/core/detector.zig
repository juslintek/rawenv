const std = @import("std");

pub const DetectionResult = struct {
    runtimes: []Entry,
    services: []Entry,

    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
        /// Service keys this entry depends on, recovered from a
        /// docker-compose.yml `depends_on:` block. Each element is a rawenv
        /// service key (e.g. "postgresql"), already resolved from the compose
        /// service name via its image. The slice is owned by the allocator
        /// passed to `detect` and freed by `deinit`; its elements are static
        /// literals (the package keys) and must not be freed individually.
        depends_on: []const []const u8 = &.{},
    };

    pub fn deinit(self: *DetectionResult, allocator: std.mem.Allocator) void {
        for (self.services) |svc| {
            if (svc.depends_on.len > 0) allocator.free(svc.depends_on);
        }
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
        // bun projects pin the runtime via the `packageManager` field (or an
        // `engines.bun` constraint). When that's present, bun — not node — is
        // the JS runtime, so detect it instead of defaulting to node.
        if (parseBunVersion(allocator, data)) |bun_version| {
            try runtimes.append(allocator, .{ .key = "bun", .value = bun_version });
        } else {
            try runtimes.append(allocator, .{
                .key = "node",
                .value = parseNodeVersion(allocator, data) orelse "22",
            });
        }
    }

    if (readFile(allocator, dir, "composer.json")) |data| {
        defer allocator.free(data);
        try runtimes.append(allocator, .{
            .key = "php",
            .value = parsePhpVersion(allocator, data) orelse "8.4",
        });
    }

    // Prefer .env, but fall back to .env.example when it's absent. Most
    // projects commit .env.example while .gitignore-ing the real .env.
    if (readFile(allocator, dir, ".env")) |data| {
        defer allocator.free(data);
        parseEnvServices(allocator, data, &services) catch {};
    } else if (readFile(allocator, dir, ".env.example")) |data| {
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

    // Python: detect from any of the common project markers. Modern projects
    // use pyproject.toml (+ uv.lock); legacy ones use requirements.txt /
    // setup.py. Only add the runtime once, preferring an explicit version from
    // pyproject.toml's `requires-python`.
    if (detectPythonVersion(allocator, dir)) |py_version| {
        try runtimes.append(allocator, .{ .key = "python", .value = py_version });
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
    // Snap the engines constraint to the nearest node major the resolver can
    // actually install, rather than echoing an arbitrary version from the
    // manifest. Returns a comptime-known literal (node_str is only read here,
    // before `parsed` is freed).
    return snapNodeVersion(node_str);
}

/// Snap a package.json `engines.node` constraint (e.g. ">=20.0.0", "^18",
/// "23.1.0") to the nearest node major rawenv's resolver supports. The
/// supported set mirrors resolver.zig's `node_releases` table — keep them in
/// sync. On a tie the higher (newer) major wins. Returns null when no numeric
/// major can be extracted.
fn snapNodeVersion(raw: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < raw.len and !std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (i >= raw.len) return null;
    const start = i;
    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    const major = std.fmt.parseInt(u32, raw[start..i], 10) catch return null;

    const supported = [_]struct { n: u32, s: []const u8 }{
        .{ .n = 18, .s = "18" },
        .{ .n = 20, .s = "20" },
        .{ .n = 22, .s = "22" },
        .{ .n = 23, .s = "23" },
    };
    var best: []const u8 = supported[0].s;
    var best_dist: u32 = std.math.maxInt(u32);
    for (supported) |c| {
        const dist = if (c.n > major) c.n - major else major - c.n;
        // `<=` lets the higher major win ties (the table is ascending).
        if (dist <= best_dist) {
            best_dist = dist;
            best = c.s;
        }
    }
    return best;
}

/// Detect a bun runtime from package.json. Bun projects pin the runtime via
/// the `packageManager` field (Corepack convention, e.g. "bun@1.2.0") or via
/// an `engines.bun` constraint. Returns a resolver-supported bun version
/// literal, or null when the manifest does not call for bun.
fn parseBunVersion(allocator: std.mem.Allocator, data: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch return null;
    defer parsed.deinit();
    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return null,
    };

    // packageManager: "bun@1.2.0"
    if (obj.get("packageManager")) |pm| {
        switch (pm) {
            .string => |s| {
                if (std.mem.startsWith(u8, s, "bun@")) return snapBunVersion(s["bun@".len..]);
            },
            else => {},
        }
    }

    // engines: { "bun": ">=1.0.0" }
    if (obj.get("engines")) |engines| {
        switch (engines) {
            .object => |eo| {
                if (eo.get("bun")) |bun_v| {
                    switch (bun_v) {
                        .string => |s| return snapBunVersion(s),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    return null;
}

/// Snap a bun version constraint (e.g. "1.2.0", ">=1.0.0", "^1") to the
/// nearest bun major rawenv's resolver supports. rawenv currently pins bun
/// 1.x, so any 1.* constraint resolves to "1". Returns null when no numeric
/// major can be extracted or the major is unsupported. Returns a comptime
/// literal (the parsed JSON is freed by the caller).
fn snapBunVersion(raw: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < raw.len and !std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (i >= raw.len) return null;
    const start = i;
    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    const major = std.fmt.parseInt(u32, raw[start..i], 10) catch return null;
    // Only bun 1.x is supported today.
    if (major == 1) return "1";
    return null;
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

/// Detect a Python runtime version by inspecting the common project markers.
/// Returns a static "major.minor" literal, or null if no Python markers exist.
/// pyproject.toml's `requires-python` is preferred for the version; other
/// markers (uv.lock, requirements.txt, setup.py, setup.cfg, Pipfile) only act
/// as presence indicators and fall back to the default version.
fn detectPythonVersion(allocator: std.mem.Allocator, dir: std.Io.Dir) ?[]const u8 {
    const default_version = "3.12";
    var found = false;
    var version: []const u8 = default_version;

    if (readFile(allocator, dir, "pyproject.toml")) |data| {
        defer allocator.free(data);
        found = true;
        if (parseRequiresPython(data)) |v| version = v;
    }

    const markers = [_][]const u8{ "uv.lock", "requirements.txt", "setup.py", "setup.cfg", "Pipfile" };
    for (markers) |marker| {
        if (found) break;
        if (readFile(allocator, dir, marker)) |data| {
            allocator.free(data);
            found = true;
        }
    }

    return if (found) version else null;
}

/// Extract a static "major.minor" Python version from a pyproject.toml's
/// `requires-python` constraint (e.g. `>=3.11`, `==3.12.*`, `>=3.9,<4.0`).
fn parseRequiresPython(data: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (!std.mem.startsWith(u8, trimmed, "requires-python")) continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        return matchPythonVersion(trimmed[eq + 1 ..]);
    }
    return null;
}

/// Map a constraint string to a static Python "major.minor" literal.
fn matchPythonVersion(raw: []const u8) ?[]const u8 {
    const versions = [_][]const u8{ "3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "3.14" };
    var i: usize = 0;
    while (i < raw.len and !std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (i >= raw.len) return null;
    const start = i;
    while (i < raw.len and (std.ascii.isDigit(raw[i]) or raw[i] == '.')) : (i += 1) {}
    var ver = raw[start..i];
    if (ver.len > 0 and ver[ver.len - 1] == '.') ver = ver[0 .. ver.len - 1];
    // Reduce a "major.minor.patch" to "major.minor".
    if (std.mem.indexOfScalar(u8, ver, '.')) |first_dot| {
        if (std.mem.indexOfScalarPos(u8, ver, first_dot + 1, '.')) |second_dot| {
            ver = ver[0..second_dot];
        }
    }
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

/// Recognised service image → rawenv package key + default version.
const ServiceInfo = struct { key: []const u8, default: []const u8 };

fn mapComposeImage(image: []const u8) ?ServiceInfo {
    const base = imageBasename(image);
    if (std.mem.startsWith(u8, base, "postgres")) return .{ .key = "postgresql", .default = "16" };
    if (std.mem.startsWith(u8, base, "redis")) return .{ .key = "redis", .default = "7" };
    if (std.mem.startsWith(u8, base, "mysql")) return .{ .key = "mysql", .default = "8" };
    if (std.mem.startsWith(u8, base, "mariadb")) return .{ .key = "mariadb", .default = "11" };
    if (std.mem.startsWith(u8, base, "mongo")) return .{ .key = "mongodb", .default = "7" };
    if (std.mem.indexOf(u8, image, "azure-sql-edge") != null or std.mem.indexOf(u8, image, "mssql") != null)
        return .{ .key = "mssql", .default = "2022" };
    if (std.mem.indexOf(u8, image, "meilisearch") != null) return .{ .key = "meilisearch", .default = "1" };
    return null;
}

/// Extract the version major from an image basename (e.g. "postgres:15" → "15"),
/// falling back to the package default when the tag is non-numeric or absent.
fn versionForImage(base: []const u8, default: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, base, ':') orelse return default;
    return matchMajor(base[colon..]) orelse default;
}

/// Parse the `services:` block of a docker-compose.yml. Two things are
/// recovered per service: the rawenv package key (from its `image:`) and its
/// `depends_on:` edges. Detected database/cache services are appended to
/// `services` (deduped by key, preserving declaration order) with their
/// `depends_on` resolved from compose service names to rawenv keys — so the
/// dependency graph survives `rawenv init` and `rawenv connections` can
/// reconstruct it. Edges whose endpoints are not recognised services (e.g. an
/// app's own runtime image, which `init` tracks as a runtime not a service)
/// are dropped, since there is no service entry to anchor them to.
fn parseDockerComposeServices(allocator: std.mem.Allocator, data: []const u8, services: *std.ArrayList(DetectionResult.Entry)) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ComposeSvc = struct {
        name: []const u8,
        info: ?ServiceInfo = null,
        version: []const u8 = "",
        deps: std.ArrayList([]const u8) = .empty, // compose service names
    };

    var svcs: std.ArrayList(ComposeSvc) = .empty;

    var in_services = false;
    var service_indent: ?usize = null;
    var prop_indent: ?usize = null;
    var cur: ?*ComposeSvc = null;
    var in_depends = false;

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |raw| {
        const line = stripCr(raw);
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const indent = leadingSpaces(line);

        if (indent == 0) {
            in_services = std.mem.eql(u8, keyOf(trimmed), "services");
            service_indent = null;
            cur = null;
            in_depends = false;
            continue;
        }
        if (!in_services) continue;

        if (service_indent == null) service_indent = indent;
        const svc_indent = service_indent.?;
        if (indent < svc_indent) continue;

        if (indent == svc_indent) {
            // New service declaration: "<name>:".
            try svcs.append(arena, .{ .name = try arena.dupe(u8, keyOf(trimmed)) });
            cur = &svcs.items[svcs.items.len - 1];
            prop_indent = null;
            in_depends = false;
            continue;
        }

        const svc = cur orelse continue;

        // List item under depends_on: "- name".
        if (std.mem.startsWith(u8, trimmed, "- ") or std.mem.eql(u8, trimmed, "-")) {
            if (in_depends) {
                const dep = unquote(std.mem.trim(u8, trimmed[1..], &std.ascii.whitespace));
                if (dep.len > 0) try svc.deps.append(arena, try arena.dupe(u8, dep));
            }
            continue;
        }

        if (prop_indent == null) prop_indent = indent;

        if (indent <= prop_indent.?) {
            // A property key line: "key:" or "key: value".
            const key = keyOf(trimmed);
            const value = valueOf(trimmed);
            in_depends = false;
            if (std.mem.eql(u8, key, "image")) {
                const image = extractImageValue(value);
                if (image.len > 0) {
                    if (mapComposeImage(image)) |info| {
                        svc.info = info;
                        svc.version = versionForImage(imageBasename(image), info.default);
                    }
                }
            } else if (std.mem.eql(u8, key, "depends_on")) {
                in_depends = true;
                // Inline array form: "depends_on: [a, b]".
                if (std.mem.indexOfScalar(u8, value, '[')) |s| {
                    const e = std.mem.indexOfScalar(u8, value, ']') orelse value.len;
                    var vit = std.mem.splitScalar(u8, value[s + 1 .. e], ',');
                    while (vit.next()) |rawv| {
                        const dv = unquote(std.mem.trim(u8, rawv, &std.ascii.whitespace));
                        if (dv.len > 0) try svc.deps.append(arena, try arena.dupe(u8, dv));
                    }
                }
            }
        } else if (in_depends and std.mem.endsWith(u8, trimmed, ":")) {
            // Long form: "depends_on:\n  <name>:\n    condition: ...".
            try svc.deps.append(arena, try arena.dupe(u8, keyOf(trimmed)));
        }
    }

    // Emit detected services (deduped by key) with resolved dependency edges.
    for (svcs.items) |*cs| {
        const info = cs.info orelse continue;
        if (hasService(services, info.key)) continue;

        var resolved: std.ArrayList([]const u8) = .empty;
        errdefer resolved.deinit(allocator);
        for (cs.deps.items) |dep_name| {
            const dep_key = blk: {
                for (svcs.items) |other| {
                    if (std.mem.eql(u8, other.name, dep_name)) {
                        if (other.info) |oi| break :blk oi.key;
                    }
                }
                break :blk null;
            };
            if (dep_key) |dk| {
                var dup = false;
                for (resolved.items) |r| {
                    if (std.mem.eql(u8, r, dk)) {
                        dup = true;
                        break;
                    }
                }
                if (!dup) try resolved.append(allocator, dk);
            }
        }

        const deps_slice: []const []const u8 = if (resolved.items.len > 0)
            try resolved.toOwnedSlice(allocator)
        else blk: {
            resolved.deinit(allocator);
            break :blk &.{};
        };

        try services.append(allocator, .{ .key = info.key, .value = cs.version, .depends_on = deps_slice });
    }
}

/// Strip a trailing carriage return (CRLF line endings).
fn stripCr(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') return line[0 .. line.len - 1];
    return line;
}

fn leadingSpaces(line: []const u8) usize {
    var n: usize = 0;
    while (n < line.len and (line[n] == ' ' or line[n] == '\t')) : (n += 1) {}
    return n;
}

/// Text before the first ':' in "key: value" (or "key:" / "name:").
fn keyOf(trimmed: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return trimmed;
    return std.mem.trim(u8, trimmed[0..colon], &std.ascii.whitespace);
}

/// Text after the first ':' in "key: value" (may be empty).
fn valueOf(trimmed: []const u8) []const u8 {
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return "";
    return std.mem.trim(u8, trimmed[colon + 1 ..], &std.ascii.whitespace);
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and ((s[0] == '"' and s[s.len - 1] == '"') or (s[0] == '\'' and s[s.len - 1] == '\''))) {
        return s[1 .. s.len - 1];
    }
    return s;
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
