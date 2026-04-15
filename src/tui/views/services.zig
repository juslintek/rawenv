const std = @import("std");
const theme = @import("../theme.zig");
const widgets = @import("../widgets.zig");
const app = @import("../app.zig");

pub fn render(writer: anytype, model: *const app.Model) !void {
    // Table header
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("  STATUS  SERVICE        VERSION    PORT   PID     CPU    MEM     UPTIME\n");
    try theme.writeReset(writer);

    for (model.services, 0..) |svc, i| {
        const selected = i == model.selected_service;
        if (selected) try theme.writeBg(writer, theme.tui_selected);
        if (std.mem.eql(u8, svc.status, "stopped")) try theme.writeFg(writer, theme.text_disabled);

        try writer.writeAll("  ");
        try widgets.statusDot(writer, svc.status);
        if (selected) try theme.writeBg(writer, theme.tui_selected);
        if (std.mem.eql(u8, svc.status, "stopped")) try theme.writeFg(writer, theme.text_disabled);

        try theme.writeBold(writer);
        try writer.print("  {s:<14}", .{svc.name});
        try theme.writeReset(writer);
        if (selected) try theme.writeBg(writer, theme.tui_selected);
        if (std.mem.eql(u8, svc.status, "stopped")) try theme.writeFg(writer, theme.text_disabled);

        try writer.print("{s:<10}", .{svc.version});
        try theme.writeFg(writer, theme.info);
        if (selected) try theme.writeBg(writer, theme.tui_selected);
        try writer.print(" {s:<6}", .{svc.port});
        try theme.writeReset(writer);
        if (selected) try theme.writeBg(writer, theme.tui_selected);
        if (std.mem.eql(u8, svc.status, "stopped")) try theme.writeFg(writer, theme.text_disabled);

        try writer.print(" {s:<7} {s:<6} {s:<7} {s}", .{ svc.pid, svc.cpu, svc.mem, svc.uptime });
        try theme.writeReset(writer);
        try writer.writeAll("\n");
    }

    // Mini log panel
    try writer.writeAll("\n");
    try theme.writeFg(writer, theme.text_secondary);
    const sel = model.services[model.selected_service];
    try writer.print("  Logs — {s}", .{sel.name});
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("  l: full logs\n");
    try theme.writeReset(writer);

    const max_logs: usize = @min(4, model.log_buffer.len);
    for (model.log_buffer[0..max_logs]) |log| {
        try writer.writeAll("  ");
        try theme.writeFg(writer, theme.text_disabled);
        try writer.print("{s} ", .{log.time});
        const c = if (std.mem.eql(u8, log.level, "error")) theme.err else if (std.mem.eql(u8, log.level, "warn")) theme.warning else theme.text_secondary;
        try theme.writeFg(writer, c);
        try writer.print("{s}\n", .{log.msg});
    }
    try theme.writeReset(writer);
}
