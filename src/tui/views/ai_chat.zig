const std = @import("std");
const theme = @import("../theme.zig");
const app = @import("../app.zig");

pub const providers = [_][]const u8{
    "Groq (Llama 3.3 70B)",
    "Cerebras (Qwen3 235B)",
    "Cloudflare Workers AI",
    "Ollama (local)",
};

pub fn render(writer: anytype, model: *const app.Model) !void {
    try theme.writeFg(writer, theme.text_secondary);
    try writer.writeAll("  AI Assistant  ");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("Tab:provider  ^L:clear\n\n");

    // Provider selector
    for (providers, 0..) |prov, i| {
        if (i == model.ai_provider) {
            try theme.writeBg(writer, theme.accent);
            try theme.writeFg(writer, .{ .r = 255, .g = 255, .b = 255 });
        } else {
            try theme.writeBg(writer, theme.bg_tertiary);
            try theme.writeFg(writer, theme.text_secondary);
        }
        try writer.print(" {s} ", .{prov});
        try theme.writeReset(writer);
    }
    try writer.writeAll("\n\n");

    // Chat messages
    for (model.chat_messages) |msg| {
        if (std.mem.eql(u8, msg.role, "user")) {
            try theme.writeFg(writer, theme.accent);
            try writer.writeAll("  > ");
        } else {
            try theme.writeFg(writer, theme.success);
            try writer.writeAll("  ◆ ");
        }
        try theme.writeFg(writer, theme.text_primary);
        try writer.print("{s}\n", .{msg.content});
    }

    // Input line
    try writer.writeAll("\n");
    try theme.writeFg(writer, theme.accent);
    try writer.writeAll("  > ");
    try theme.writeFg(writer, theme.text_disabled);
    try writer.writeAll("Ask about your environment...\n");
    try theme.writeReset(writer);
}
