const std = @import("std");

pub const Provider = enum { groq, cerebras, cloudflare, ollama, custom };

pub const ProviderConfig = struct {
    endpoint: []const u8,
    api_key: []const u8 = "",
    model: []const u8,
    max_tokens: u32 = 500,
};

pub const Message = struct {
    role: Role,
    content: []const u8,

    pub const Role = enum { system, user, assistant };

    pub fn roleStr(self: Message) []const u8 {
        return switch (self.role) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
        };
    }
};

pub fn defaultConfig(p: Provider) ProviderConfig {
    return switch (p) {
        .groq => .{ .endpoint = "https://api.groq.com/openai/v1/chat/completions", .model = "llama-3.3-70b-versatile" },
        .cerebras => .{ .endpoint = "https://api.cerebras.ai/v1/chat/completions", .model = "llama-3.3-70b" },
        .cloudflare => .{ .endpoint = "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1/chat/completions", .model = "@cf/meta/llama-3.3-70b-instruct-fp8-fast" },
        .ollama => .{ .endpoint = "http://localhost:11434/v1/chat/completions", .model = "llama3" },
        .custom => .{ .endpoint = "", .model = "" },
    };
}

pub fn envKeyName(p: Provider) []const u8 {
    return switch (p) {
        .groq => "GROQ_API_KEY",
        .cerebras => "CEREBRAS_API_KEY",
        .cloudflare => "CLOUDFLARE_API_KEY",
        .ollama => "",
        .custom => "",
    };
}

pub const SendError = error{
    HttpError,
    RateLimited,
    ParseError,
    ConnectionRefused,
} || std.mem.Allocator.Error;

pub fn sendMessage(_: std.mem.Allocator, _: ProviderConfig, _: []const Message) SendError!struct { body: []u8, status: std.http.Status } {
    // TODO: std.http.Client requires Io in Zig 0.16.0
    return error.ConnectionRefused;
}

fn writeJsonEscaped(writer: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}

pub fn parseResponseContent(_: std.mem.Allocator, json_body: []const u8) ?[]const u8 {
    const needle = "\"content\":\"";
    const start = std.mem.indexOf(u8, json_body, needle) orelse return null;
    const content_start = start + needle.len;
    var i: usize = content_start;
    while (i < json_body.len) : (i += 1) {
        if (json_body[i] == '\\') {
            i += 1;
            continue;
        }
        if (json_body[i] == '"') break;
    }
    if (i >= json_body.len) return null;
    return json_body[content_start..i];
}
