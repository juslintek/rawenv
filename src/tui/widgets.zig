const theme = @import("theme.zig");

pub fn statusDot(writer: anytype, status: []const u8) !void {
    const c = if (std.mem.eql(u8, status, "running")) theme.success else if (std.mem.eql(u8, status, "warning")) theme.warning else theme.err;
    try theme.writeFg(writer, c);
    try writer.writeAll("●");
    try theme.writeReset(writer);
}

pub fn progressBar(writer: anytype, pct: u8, width: u16) !void {
    const filled: u16 = @intCast(@as(u32, width) * pct / 100);
    try theme.writeFg(writer, if (pct > 80) theme.warning else if (pct > 50) theme.accent else theme.success);
    for (0..filled) |_| try writer.writeAll("█");
    try theme.writeFg(writer, theme.bg_tertiary);
    for (0..width - filled) |_| try writer.writeAll("░");
    try theme.writeReset(writer);
}

pub fn tabBar(writer: anytype, tabs: []const []const u8, active: usize) !void {
    for (tabs, 0..) |tab, i| {
        if (i == active) {
            try theme.writeBg(writer, theme.bg_tertiary);
            try theme.writeFg(writer, theme.text_primary);
            try theme.writeBold(writer);
        } else {
            try theme.writeFg(writer, theme.text_secondary);
        }
        try writer.print(" {s} ", .{tab});
        try theme.writeReset(writer);
    }
    try writer.writeAll("\n");
}

pub fn keyHints(writer: anytype, hints: []const [2][]const u8) !void {
    for (hints, 0..) |hint, i| {
        if (i > 0) try writer.writeAll(" ");
        try theme.writeFg(writer, theme.accent);
        try writer.writeAll(hint[0]);
        try theme.writeFg(writer, theme.text_secondary);
        try writer.print(":{s}", .{hint[1]});
    }
    try theme.writeReset(writer);
}

const std = @import("std");
