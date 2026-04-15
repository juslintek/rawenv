const std = @import("std");
const theme = @import("../theme.zig");
const app = @import("../app.zig");

pub const ConfigMode = enum { view, edit, diff, reset };

pub fn render(writer: anytype, model: *const app.Model) !void {
    const sel = model.services[model.selected_service];
    // Mode bar
    try theme.writeFg(writer, theme.text_secondary);
    try writer.print("  Config — {s}  ", .{sel.name});
    const modes = [_][]const u8{ "view", "e:edit", "d:diff", "r:reset" };
    const mode_enums = [_]ConfigMode{ .view, .edit, .diff, .reset };
    for (modes, mode_enums) |label, m| {
        if (model.config_mode == m) {
            try theme.writeBg(writer, theme.accent);
            try theme.writeFg(writer, .{ .r = 255, .g = 255, .b = 255 });
        } else {
            try theme.writeBg(writer, theme.bg_tertiary);
            try theme.writeFg(writer, theme.text_secondary);
        }
        try writer.print(" {s} ", .{label});
        try theme.writeReset(writer);
    }
    try writer.writeAll("\n\n");

    switch (model.config_mode) {
        .view => try renderView(writer, sel),
        .edit => try renderEdit(writer, sel),
        .diff => try renderDiff(writer, sel),
        .reset => try renderReset(writer, sel),
    }
}

const ConfigEntry = struct { key: []const u8, val: []const u8 };

fn getConfig(svc: app.Service) []const ConfigEntry {
    if (std.mem.eql(u8, svc.name, "PostgreSQL")) return &pg_config;
    if (std.mem.eql(u8, svc.name, "Redis")) return &redis_config;
    return &default_config;
}

const pg_config = [_]ConfigEntry{
    .{ .key = "port", .val = "5432" },
    .{ .key = "max_connections", .val = "20" },
    .{ .key = "shared_buffers", .val = "64MB" },
    .{ .key = "listen_addresses", .val = "127.0.0.1" },
};
const redis_config = [_]ConfigEntry{
    .{ .key = "port", .val = "6379" },
    .{ .key = "bind", .val = "127.0.0.1" },
    .{ .key = "maxmemory", .val = "64mb" },
};
const default_config = [_]ConfigEntry{
    .{ .key = "status", .val = "no config" },
};

fn renderView(writer: anytype, svc: app.Service) !void {
    for (getConfig(svc)) |entry| {
        try theme.writeFg(writer, theme.accent);
        try writer.print("  {s:<20}", .{entry.key});
        try theme.writeFg(writer, theme.text_primary);
        try writer.print("{s}\n", .{entry.val});
    }
    try theme.writeReset(writer);
}

fn renderEdit(writer: anytype, svc: app.Service) !void {
    for (getConfig(svc)) |entry| {
        try theme.writeFg(writer, theme.accent);
        try writer.print("  {s:<20}", .{entry.key});
        try theme.writeFg(writer, theme.text_primary);
        try writer.print("[{s}]\n", .{entry.val});
    }
    try theme.writeReset(writer);
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("\n  Tab/Shift+Tab: navigate · Enter: save · Esc: cancel\n");
    try theme.writeReset(writer);
}

fn renderDiff(writer: anytype, _: app.Service) !void {
    const diffs = [_][3][]const u8{
        .{ "max_connections", "100", "20" },
        .{ "shared_buffers", "128MB", "64MB" },
        .{ "effective_cache_size", "4GB", "256MB" },
    };
    for (diffs) |d| {
        try theme.writeFg(writer, theme.accent);
        try writer.print("  {s}\n", .{d[0]});
        try theme.writeFg(writer, theme.err);
        try writer.print("    - {s}\n", .{d[1]});
        try theme.writeFg(writer, theme.success);
        try writer.print("    + {s}\n", .{d[2]});
    }
    try theme.writeReset(writer);
}

fn renderReset(writer: anytype, svc: app.Service) !void {
    try theme.writeFg(writer, theme.warning);
    try writer.print("  ⚠️  Reset {s} to defaults?\n\n", .{svc.name});
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("  This will replace rawenv's optimized config with defaults.\n\n");
    try theme.writeFg(writer, theme.accent);
    try writer.writeAll("  max_connections");
    try theme.writeFg(writer, theme.text_primary);
    try writer.writeAll(": 20 → ");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("100\n");
    try theme.writeFg(writer, theme.accent);
    try writer.writeAll("  shared_buffers");
    try theme.writeFg(writer, theme.text_primary);
    try writer.writeAll(": 64MB → ");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("128MB\n\n");
    try theme.writeFg(writer, theme.warning);
    try writer.writeAll("  [Reset & Restart]");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("  [Cancel]\n");
    try theme.writeReset(writer);
}
