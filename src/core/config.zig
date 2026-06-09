const std = @import("std");

pub const Config = struct {
    project_name: []const u8 = "",
    runtimes: []Entry = &.{},
    services: []Entry = &.{},
    auto_detect: bool = false,

    /// A service/runtime entry. For instances like [services.postgres.primary],
    /// `key` is the full instance id ("postgres.primary"), `service_type` is the
    /// base type ("postgres"), and `port` is an explicit override (0 = auto).
    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
        port: u16 = 0,
        service_type: []const u8 = "",

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

const SectionKind = enum { none, project, runtimes, services, detect, runtime_item, service_item };

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Config {
    var cfg = Config{};
    var runtimes: std.ArrayList(Config.Entry) = .empty;
    errdefer runtimes.deinit(allocator);
    var services: std.ArrayList(Config.Entry) = .empty;
    errdefer services.deinit(allocator);
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
                section = .service_item;
                current_item_name = name["services.".len..];
                const dot = std.mem.indexOfScalar(u8, current_item_name, '.');
                const base = if (dot) |d| current_item_name[0..d] else current_item_name;
                try services.append(allocator, .{
                    .key = current_item_name,
                    .value = "latest",
                    .service_type = base,
                    .port = 0,
                });
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
            if (svc.port != 0 or std.mem.indexOfScalar(u8, svc.key, '.') != null) needs_sections = true;
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
    allocator.free(cfg.runtimes);
    allocator.free(cfg.services);
    cfg.* = .{};
}
