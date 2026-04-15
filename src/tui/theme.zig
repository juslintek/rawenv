// Theme colors from design/tokens/tokens.json — TUI ANSI approximations
pub const Color = struct { r: u8, g: u8, b: u8 };

pub fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b };
}

// Background
pub const bg_primary = rgb(15, 15, 20);
pub const bg_secondary = rgb(22, 22, 30);
pub const bg_tertiary = rgb(30, 30, 42);

// Accent
pub const accent = rgb(99, 102, 241);
pub const accent_secondary = rgb(129, 140, 248);
pub const success = rgb(52, 211, 153);
pub const warning = rgb(251, 191, 36);
pub const err = rgb(248, 113, 113);
pub const info = rgb(96, 165, 250);

// Text
pub const text_primary = rgb(226, 228, 240);
pub const text_secondary = rgb(139, 141, 166);
pub const text_disabled = rgb(74, 75, 94);

// TUI specific
pub const tui_header = accent;
pub const tui_selected = bg_tertiary;
pub const tui_chart_bar = accent_secondary;

// Border
pub const border = rgb(42, 42, 58);

pub fn fgSeq(c: Color) [19]u8 {
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b }) catch unreachable;
    return buf;
}

pub fn bgSeq(c: Color) [19]u8 {
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b }) catch unreachable;
    return buf;
}

const std = @import("std");

pub fn writeFg(writer: anytype, c: Color) !void {
    try writer.print("\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
}

pub fn writeBg(writer: anytype, c: Color) !void {
    try writer.print("\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
}

pub fn writeReset(writer: anytype) !void {
    try writer.writeAll("\x1b[0m");
}

pub fn writeBold(writer: anytype) !void {
    try writer.writeAll("\x1b[1m");
}
