const std = @import("std");

pub const Config = struct {
    project_name: []const u8 = "",
    runtimes: []Entry = &.{},
    services: []Entry = &.{},
    auto_detect: bool = false,

    pub const Entry = struct { key: []const u8, value: []const u8 };
};

pub const ParseError = error{
    InvalidToml,
    MissingProjectName,
};

const Section = enum { none, project, runtimes, services, detect };

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Config {
    var cfg = Config{};
    var runtimes: std.ArrayList(Config.Entry) = .empty;
    errdefer runtimes.deinit(allocator);
    var services: std.ArrayList(Config.Entry) = .empty;
    errdefer services.deinit(allocator);
    var section: Section = .none;

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
            .runtimes => try runtimes.append(allocator, .{
                .key = key,
                .value = stripQuotes(val_raw) orelse return ParseError.InvalidToml,
            }),
            .services => try services.append(allocator, .{
                .key = key,
                .value = stripQuotes(val_raw) orelse return ParseError.InvalidToml,
            }),
            .detect => {
                if (std.mem.eql(u8, key, "auto"))
                    cfg.auto_detect = std.mem.eql(u8, val_raw, "true");
            },
            .none => return ParseError.InvalidToml,
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

    try buf.print(allocator, "[project]\nname = \"{s}\"\n", .{project_name});

    if (runtimes.len > 0) {
        try buf.appendSlice(allocator, "\n[runtimes]\n");
        for (runtimes) |rt| try buf.print(allocator, "{s} = \"{s}\"\n", .{ rt.key, rt.value });
    }

    if (services.len > 0) {
        try buf.appendSlice(allocator, "\n[services]\n");
        for (services) |svc| try buf.print(allocator, "{s} = \"{s}\"\n", .{ svc.key, svc.value });
    }

    try buf.appendSlice(allocator, "\n[detect]\nauto = true\n");

    return try buf.toOwnedSlice(allocator);
}

pub fn deinit(allocator: std.mem.Allocator, cfg: *Config) void {
    allocator.free(cfg.runtimes);
    allocator.free(cfg.services);
    cfg.* = .{};
}
