const std = @import("std");
const theme = @import("../theme.zig");
const widgets = @import("../widgets.zig");
const app = @import("../app.zig");

pub const ResourceMode = enum { table, graph, tree };

pub fn render(writer: anytype, model: *const app.Model) !void {
    // Mode bar
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("  Resources  ");
    const modes = [_][]const u8{ "s:table", "g:graph", "p:tree" };
    const mode_enums = [_]ResourceMode{ .table, .graph, .tree };
    for (modes, mode_enums) |label, m| {
        if (model.resource_mode == m) {
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

    switch (model.resource_mode) {
        .table => try renderTable(writer, model),
        .graph => try renderGraph(writer, model),
        .tree => try renderTree(writer, model),
    }
}

fn renderTable(writer: anytype, model: *const app.Model) !void {
    // System overview bars
    const bars = [_]struct { label: []const u8, pct: u8, detail: []const u8 }{
        .{ .label = "CPU", .pct = 12, .detail = "12% (4 cores)" },
        .{ .label = "MEM", .pct = 14, .detail = "462MB / 32GB" },
        .{ .label = "DSK", .pct = 3, .detail = "2.0GB total" },
    };
    for (bars) |bar| {
        try theme.writeFg(writer, theme.text_secondary);
        try writer.print("  {s:<4}", .{bar.label});
        try widgets.progressBar(writer, bar.pct, 30);
        try theme.writeFg(writer, theme.text_primary);
        try writer.print("  {s}\n", .{bar.detail});
    }

    // Per-service table
    try writer.writeAll("\n");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("  SERVICE        CPU    MEM     DISK    CELL  PROCS\n");
    try theme.writeReset(writer);

    for (model.services) |svc| {
        if (std.mem.eql(u8, svc.status, "stopped")) {
            try theme.writeFg(writer, theme.text_disabled);
            try writer.print("  {s:<14} —      —       —       —     —\n", .{svc.name});
        } else {
            try theme.writeFg(writer, theme.text_primary);
            try writer.print("  {s:<14} {s:<6} {s:<7} —       ", .{ svc.name, svc.cpu, svc.mem });
            try widgets.statusDot(writer, "running");
            try writer.writeAll("     —\n");
        }
    }
    try theme.writeReset(writer);
}

fn renderGraph(writer: anytype, model: *const app.Model) !void {
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("  Memory Usage (per service)\n\n");

    for (model.services) |svc| {
        if (std.mem.eql(u8, svc.status, "stopped")) continue;
        try theme.writeFg(writer, theme.text_primary);
        try writer.print("  {s:<14}", .{svc.name});
        // Parse mem string to approximate bar width
        const bar_w: u8 = if (std.mem.eql(u8, svc.mem, "210MB")) 21 else if (std.mem.eql(u8, svc.mem, "156MB")) 16 else if (std.mem.eql(u8, svc.mem, "84MB")) 8 else 2;
        try theme.writeFg(writer, theme.tui_chart_bar);
        for (0..bar_w) |_| try writer.writeAll("█");
        try theme.writeFg(writer, theme.text_secondary);
        try writer.print(" {s}\n", .{svc.mem});
    }
    try theme.writeReset(writer);
}

fn renderTree(writer: anytype, model: *const app.Model) !void {
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("  rawenv (PID 1200) — manager\n");

    for (model.services, 0..) |svc, i| {
        const is_last = i == model.services.len - 1;
        const prefix: []const u8 = if (is_last) "  └─ " else "  ├─ ";
        try writer.writeAll(prefix);
        try widgets.statusDot(writer, svc.status);
        try writer.writeAll(" ");
        try theme.writeFg(writer, theme.accent);
        try writer.print("{s}", .{svc.name});
        try theme.writeReset(writer);
        if (std.mem.eql(u8, svc.status, "stopped")) {
            try theme.writeFg(writer, theme.text_disabled);
            try writer.writeAll(" (stopped)\n");
        } else {
            try writer.print(" (PID {s}) CPU {s} MEM {s}\n", .{ svc.pid, svc.cpu, svc.mem });
        }
    }
    try theme.writeReset(writer);
}
