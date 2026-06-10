const std = @import("std");

pub const Config = struct {
    project_name: []const u8 = "",
    runtimes: []Entry = &.{},
    services: []Entry = &.{},
    auto_detect: bool = false,

    /// Readiness/health-check policy for a service, configured via
    /// `[services.X.health]` in rawenv.toml. `rawenv up` polls each started
    /// service until it becomes ready (or the timeout elapses).
    pub const HealthCheck = struct {
        /// Probe strategy. `.auto` picks TCP for datastores and HTTP for web
        /// services. `.none` disables readiness gating for the service.
        kind: Kind = .auto,
        /// Maximum time to wait for readiness, in seconds.
        timeout_secs: u32 = 30,
        /// Request path for HTTP probes (ignored for TCP).
        path: []const u8 = "/",
        /// Port to probe. 0 means "use the service's resolved port".
        port: u16 = 0,

        pub const Kind = enum { auto, tcp, http, none };
    };

    /// An environment variable for a service, configured via a
    /// `[services.X.env]` table in rawenv.toml. Both fields borrow from the
    /// parsed input; the outer array is owned and freed by `deinit`.
    pub const EnvVar = struct {
        name: []const u8,
        value: []const u8,
    };

    /// A service/runtime entry. For instances like [services.postgres.primary],
    /// `key` is the full instance id ("postgres.primary"), `service_type` is the
    /// base type ("postgres"), and `port` is an explicit override (0 = auto).
    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
        port: u16 = 0,
        service_type: []const u8 = "",
        health: HealthCheck = .{},
        /// Names of services this entry depends on, configured via
        /// `depends_on = ["postgres", "redis"]` under `[services.X]`. Each name
        /// matches another service by full key or by base type. `rawenv up`
        /// starts dependencies first; `rawenv down` stops them last. The slice
        /// elements are borrowed from the parsed input; the outer array is
        /// owned and freed by `deinit`.
        depends_on: []const []const u8 = &.{},
        /// Environment variables for the service, configured via a
        /// `[services.X.env]` table. The outer array is owned and freed by
        /// `deinit`; the element strings borrow from the parsed input.
        env: []const EnvVar = &.{},
        /// True when this entry is the project's *own application* rather than
        /// an installable upstream service. Set explicitly via `app = true`
        /// under `[services.X]`. The project app has no downloadable artifact,
        /// so it must never be routed through the package resolver/installer
        /// (`rawenv add`) nor warned about as a missing binary. See
        /// `service.isProjectApp`, which also infers this for unmarked entries.
        app: bool = false,

        /// Base service type: the part before the first '.', or the whole key.
        pub fn baseType(self: Entry) []const u8 {
            if (self.service_type.len > 0) return self.service_type;
            const dot = std.mem.indexOfScalar(u8, self.key, '.') orelse return self.key;
            return self.key[0..dot];
        }
    };
};

pub const ParseError = error{
    InvalidToml,
    MissingProjectName,
};

const SectionKind = enum { none, project, runtimes, services, detect, runtime_item, service_item, service_health, service_env };

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Config {
    var cfg = Config{};
    var runtimes: std.ArrayList(Config.Entry) = .empty;
    errdefer runtimes.deinit(allocator);
    var services: std.ArrayList(Config.Entry) = .empty;
    errdefer {
        for (services.items) |svc| {
            if (svc.depends_on.len > 0) allocator.free(svc.depends_on);
            if (svc.env.len > 0) allocator.free(svc.env);
        }
        services.deinit(allocator);
    }
    var section: SectionKind = .none;
    var current_item_name: []const u8 = "";

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[') {
            if (line[line.len - 1] != ']') return ParseError.InvalidToml;
            const name = std.mem.trim(u8, line[1 .. line.len - 1], &std.ascii.whitespace);
            if (std.mem.eql(u8, name, "project")) {
                section = .project;
            } else if (std.mem.eql(u8, name, "runtimes")) {
                section = .runtimes;
            } else if (std.mem.eql(u8, name, "services")) {
                section = .services;
            } else if (std.mem.eql(u8, name, "detect")) {
                section = .detect;
            } else if (std.mem.startsWith(u8, name, "runtimes.")) {
                section = .runtime_item;
                current_item_name = name["runtimes.".len..];
            } else if (std.mem.startsWith(u8, name, "services.")) {
                const sub = name["services.".len..];
                if (std.mem.endsWith(u8, sub, ".health")) {
                    // [services.X.health] attaches a readiness policy to an
                    // already-declared service rather than defining a new one.
                    section = .service_health;
                    current_item_name = sub[0 .. sub.len - ".health".len];
                } else if (std.mem.endsWith(u8, sub, ".env")) {
                    // [services.X.env] attaches environment variables to an
                    // already-declared service rather than defining a new one.
                    section = .service_env;
                    current_item_name = sub[0 .. sub.len - ".env".len];
                } else {
                    section = .service_item;
                    current_item_name = sub;
                    const dot = std.mem.indexOfScalar(u8, current_item_name, '.');
                    const base = if (dot) |d| current_item_name[0..d] else current_item_name;
                    try services.append(allocator, .{
                        .key = current_item_name,
                        .value = "latest",
                        .service_type = base,
                        .port = 0,
                    });
                }
            } else {
                return ParseError.InvalidToml;
            }
            continue;
        }

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return ParseError.InvalidToml;
        const key = std.mem.trim(u8, line[0..eq_idx], &std.ascii.whitespace);
        const val_raw = std.mem.trim(u8, line[eq_idx + 1 ..], &std.ascii.whitespace);

        switch (section) {
            .project => {
                if (std.mem.eql(u8, key, "name"))
                    cfg.project_name = stripQuotes(val_raw) orelse return ParseError.InvalidToml;
            },
            .none => {
                // Top-level keys (rawenv.toml format: name = "x" at root)
                if (std.mem.eql(u8, key, "name"))
                    cfg.project_name = stripQuotes(val_raw) orelse return ParseError.InvalidToml
                else if (std.mem.eql(u8, key, "version")) {
                    // project version — ignored for now
                } else return ParseError.InvalidToml;
            },
            .runtimes => try runtimes.append(allocator, .{
                .key = key,
                .value = stripQuotes(val_raw) orelse return ParseError.InvalidToml,
            }),
            .services => try services.append(allocator, .{
                .key = key,
                .value = stripQuotes(val_raw) orelse return ParseError.InvalidToml,
            }),
            .runtime_item => {
                // [runtimes.node] format: version = "22"
                if (std.mem.eql(u8, key, "version")) {
                    try runtimes.append(allocator, .{
                        .key = current_item_name,
                        .value = stripQuotes(val_raw) orelse return ParseError.InvalidToml,
                    });
                }
            },
            .service_item => {
                // [services.postgres] or [services.postgres.primary]: version = "16", port = 5433
                if (services.items.len == 0) return ParseError.InvalidToml;
                const last = &services.items[services.items.len - 1];
                if (std.mem.eql(u8, key, "version")) {
                    last.value = stripQuotes(val_raw) orelse return ParseError.InvalidToml;
                } else if (std.mem.eql(u8, key, "port")) {
                    last.port = std.fmt.parseInt(u16, val_raw, 10) catch return ParseError.InvalidToml;
                } else if (std.mem.eql(u8, key, "depends_on")) {
                    // depends_on = ["postgres", "redis"] — start-ordering hints.
                    if (last.depends_on.len > 0) allocator.free(last.depends_on);
                    last.depends_on = try parseStringArray(allocator, val_raw);
                } else if (std.mem.eql(u8, key, "app")) {
                    // app = true marks the project's own application — a
                    // first-party service that rawenv must not try to install.
                    last.app = std.mem.eql(u8, val_raw, "true");
                }
            },
            .service_health => {
                // [services.X.health]: type/timeout/path/port. Locate the
                // matching service by key (it must be declared above).
                var target: ?*Config.Entry = null;
                for (services.items) |*svc| {
                    if (std.mem.eql(u8, svc.key, current_item_name)) {
                        target = svc;
                        break;
                    }
                }
                if (target) |t| {
                    if (std.mem.eql(u8, key, "type") or std.mem.eql(u8, key, "kind")) {
                        const v = stripQuotes(val_raw) orelse val_raw;
                        if (std.mem.eql(u8, v, "tcp")) {
                            t.health.kind = .tcp;
                        } else if (std.mem.eql(u8, v, "http")) {
                            t.health.kind = .http;
                        } else if (std.mem.eql(u8, v, "none")) {
                            t.health.kind = .none;
                        } else if (std.mem.eql(u8, v, "auto")) {
                            t.health.kind = .auto;
                        } else {
                            return ParseError.InvalidToml;
                        }
                    } else if (std.mem.eql(u8, key, "timeout")) {
                        t.health.timeout_secs = std.fmt.parseInt(u32, val_raw, 10) catch return ParseError.InvalidToml;
                    } else if (std.mem.eql(u8, key, "path")) {
                        t.health.path = stripQuotes(val_raw) orelse return ParseError.InvalidToml;
                    } else if (std.mem.eql(u8, key, "port")) {
                        t.health.port = std.fmt.parseInt(u16, val_raw, 10) catch return ParseError.InvalidToml;
                    }
                }
            },
            .service_env => {
                // [services.X.env]: KEY = "value". Append to the matching
                // service (which must be declared above). Grows the env slice
                // by one per entry — env tables are small, so the cost is
                // negligible and ownership stays simple.
                var target: ?*Config.Entry = null;
                for (services.items) |*svc| {
                    if (std.mem.eql(u8, svc.key, current_item_name)) {
                        target = svc;
                        break;
                    }
                }
                if (target) |t| {
                    const value = stripQuotes(val_raw) orelse val_raw;
                    const old = t.env;
                    const grown = try allocator.alloc(Config.EnvVar, old.len + 1);
                    @memcpy(grown[0..old.len], old);
                    grown[old.len] = .{ .name = key, .value = value };
                    if (old.len > 0) allocator.free(old);
                    t.env = grown;
                }
            },
            .detect => {
                if (std.mem.eql(u8, key, "auto"))
                    cfg.auto_detect = std.mem.eql(u8, val_raw, "true");
            },
        }
    }

    if (cfg.project_name.len == 0) return ParseError.MissingProjectName;

    cfg.runtimes = try runtimes.toOwnedSlice(allocator);
    cfg.services = try services.toOwnedSlice(allocator);
    return cfg;
}

fn stripQuotes(s: []const u8) ?[]const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return null;
}

/// Parse a TOML inline array of quoted strings, e.g. `["postgres", "redis"]`.
/// Returns an owned slice whose elements borrow from `raw` (no copies). An
/// empty array yields a non-owned empty slice. Caller frees the slice when
/// non-empty (see `deinit`).
fn parseStringArray(allocator: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    const open = std.mem.indexOfScalar(u8, raw, '[') orelse return ParseError.InvalidToml;
    const close = std.mem.lastIndexOfScalar(u8, raw, ']') orelse return ParseError.InvalidToml;
    if (close < open) return ParseError.InvalidToml;

    var items: std.ArrayList([]const u8) = .empty;
    errdefer items.deinit(allocator);

    var it = std.mem.splitScalar(u8, raw[open + 1 .. close], ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        const val = stripQuotes(trimmed) orelse return ParseError.InvalidToml;
        try items.append(allocator, val);
    }

    if (items.items.len == 0) {
        items.deinit(allocator);
        return &.{};
    }
    return items.toOwnedSlice(allocator);
}

pub fn generate(allocator: std.mem.Allocator, project_name: []const u8, runtimes: []const Config.Entry, services: []const Config.Entry) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "[project]\nname = \"");
    try buf.appendSlice(allocator, project_name);
    try buf.appendSlice(allocator, "\"\n");

    if (runtimes.len > 0) {
        try buf.appendSlice(allocator, "\n[runtimes]\n");
        for (runtimes) |rt| {
            try buf.appendSlice(allocator, rt.key);
            try buf.appendSlice(allocator, " = \"");
            try buf.appendSlice(allocator, rt.value);
            try buf.appendSlice(allocator, "\"\n");
        }
    }

    if (services.len > 0) {
        var needs_sections = false;
        for (services) |svc| {
            if (svc.port != 0 or svc.app or std.mem.indexOfScalar(u8, svc.key, '.') != null) needs_sections = true;
        }
        if (needs_sections) {
            for (services) |svc| {
                try buf.appendSlice(allocator, "\n[services.");
                try buf.appendSlice(allocator, svc.key);
                try buf.appendSlice(allocator, "]\nversion = \"");
                try buf.appendSlice(allocator, svc.value);
                try buf.appendSlice(allocator, "\"\n");
                if (svc.port != 0) {
                    try buf.print(allocator, "port = {d}\n", .{svc.port});
                }
                if (svc.app) {
                    try buf.appendSlice(allocator, "app = true\n");
                }
            }
        } else {
            try buf.appendSlice(allocator, "\n[services]\n");
            for (services) |svc| {
                try buf.appendSlice(allocator, svc.key);
                try buf.appendSlice(allocator, " = \"");
                try buf.appendSlice(allocator, svc.value);
                try buf.appendSlice(allocator, "\"\n");
            }
        }
    }

    try buf.appendSlice(allocator, "\n[detect]\nauto = true\n");

    return try buf.toOwnedSlice(allocator);
}

pub fn deinit(allocator: std.mem.Allocator, cfg: *Config) void {
    for (cfg.services) |svc| {
        if (svc.depends_on.len > 0) allocator.free(svc.depends_on);
        if (svc.env.len > 0) allocator.free(svc.env);
    }
    allocator.free(cfg.runtimes);
    allocator.free(cfg.services);
    cfg.* = .{};
}
