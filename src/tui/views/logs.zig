const std = @import("std");
const theme = @import("../theme.zig");
const app = @import("../app.zig");

pub fn render(writer: anytype, model: *const app.Model) !void {
    const sel = model.services[model.selected_service];
    try theme.writeFg(writer, theme.text_secondary);
    try writer.print("  Logs — {s}", .{sel.name});
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("  f:filter  /:search  c:clear  w:wrap  ↑↓:scroll\n\n");
    try theme.writeReset(writer);

    const start = if (model.log_buffer.len > model.log_scroll + 20) model.log_scroll else 0;
    const end = @min(start + 20, model.log_buffer.len);
    for (model.log_buffer[start..end]) |log| {
        try writer.writeAll("  ");
        try theme.writeFg(writer, theme.text_disabled);
        try writer.print("{s} ", .{log.time});
        const c = if (std.mem.eql(u8, log.level, "error")) theme.err else if (std.mem.eql(u8, log.level, "warn")) theme.warning else if (std.mem.eql(u8, log.level, "active")) theme.text_primary else theme.text_secondary;
        try theme.writeFg(writer, c);
        try writer.print("{s}\n", .{log.msg});
    }
    try theme.writeReset(writer);

    try writer.writeAll("\n");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.print("  Showing {d} lines  Auto-scroll: ON\n", .{model.log_buffer.len});
    try theme.writeReset(writer);
}
