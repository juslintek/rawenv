const std = @import("std");

pub const Provider = enum { groq, cerebras, cloudflare, ollama, custom };

pub const ProviderConfig = struct {
    endpoint: []const u8,
    api_key: []const u8 = "",
    model: []const u8,
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

pub const SendError = error{
    HttpError,
    RateLimited,
    ParseError,
    ConnectionRefused,
} || std.mem.Allocator.Error;

pub fn sendMessage(allocator: std.mem.Allocator, cfg: ProviderConfig, messages: []const Message) SendError!struct { body: []u8, status: std.http.Status } {
    // Build JSON payload
    var payload_buf: std.ArrayList(u8) = .empty;
    defer payload_buf.deinit(allocator);
    const w = payload_buf.writer(allocator);

    w.writeAll("{\"model\":\"") catch return SendError.HttpError;
    w.writeAll(cfg.model) catch return SendError.HttpError;
    w.writeAll("\",\"messages\":[") catch return SendError.HttpError;
    for (messages, 0..) |msg, i| {
        if (i > 0) w.writeByte(',') catch return SendError.HttpError;
        w.writeAll("{\"role\":\"") catch return SendError.HttpError;
        w.writeAll(msg.roleStr()) catch return SendError.HttpError;
        w.writeAll("\",\"content\":\"") catch return SendError.HttpError;
        writeJsonEscaped(w, msg.content) catch return SendError.HttpError;
        w.writeAll("\"}") catch return SendError.HttpError;
    }
    w.writeAll("],\"max_tokens\":500,\"temperature\":0.7}") catch return SendError.HttpError;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const auth_header: []const std.http.Header = if (cfg.api_key.len > 0) &.{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = cfg.api_key },
    } else &.{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    // Response writer
    var resp_writer = std.Io.Writer.Allocating.init(allocator);
    defer resp_writer.deinit();

    const result = client.fetch(.{
        .location = .{ .url = cfg.endpoint },
        .method = .POST,
        .payload = payload_buf.items,
        .extra_headers = auth_header,
        .response_writer = &resp_writer.writer,
    }) catch return SendError.ConnectionRefused;

    if (result.status == .too_many_requests) return SendError.RateLimited;
    if (result.status != .ok) return SendError.HttpError;

    return .{ .body = try resp_writer.toOwnedSlice(), .status = result.status };
}

fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
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
