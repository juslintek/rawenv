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

pub fn sendMessage(allocator: std.mem.Allocator, cfg: ProviderConfig, messages: []const Message) SendError!struct { body: []u8, status: std.http.Status } {
    // Build JSON payload using Allocating writer
    var payload: std.Io.Writer.Allocating = .init(allocator);
    defer payload.deinit();
    const pw = &payload.writer;

    pw.writeAll("{\"model\":\"") catch return error.HttpError;
    writeJsonEscaped(pw, cfg.model) catch return error.HttpError;
    pw.print("\",\"max_tokens\":{d},\"temperature\":0.7,\"messages\":[", .{cfg.max_tokens}) catch return error.HttpError;
    for (messages, 0..) |msg, i| {
        if (i > 0) pw.writeByte(',') catch return error.HttpError;
        pw.writeAll("{\"role\":\"") catch return error.HttpError;
        pw.writeAll(msg.roleStr()) catch return error.HttpError;
        pw.writeAll("\",\"content\":\"") catch return error.HttpError;
        writeJsonEscaped(pw, msg.content) catch return error.HttpError;
        pw.writeAll("\"}") catch return error.HttpError;
    }
    pw.writeAll("]}") catch return error.HttpError;
    pw.flush() catch return error.HttpError;

    // Build auth header value
    var auth_buf: [512]u8 = undefined;
    const auth_val = if (cfg.api_key.len > 0) std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{cfg.api_key}) catch return error.HttpError else null;

    const extra_headers: []const std.http.Header = if (auth_val) |av| &.{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Authorization", .value = av },
    } else &.{
        .{ .name = "Content-Type", .value = "application/json" },
    };

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var resp: std.Io.Writer.Allocating = .init(allocator);
    errdefer resp.deinit();

    const result = client.fetch(.{
        .location = .{ .url = cfg.endpoint },
        .method = .POST,
        .payload = payload.written(),
        .extra_headers = extra_headers,
        .response_writer = &resp.writer,
    }) catch return error.ConnectionRefused;

    resp.writer.flush() catch return error.HttpError;

    if (result.status == .too_many_requests) {
        resp.deinit();
        return error.RateLimited;
    }
    if (result.status != .ok) {
        resp.deinit();
        return error.HttpError;
    }

    return .{ .body = resp.toOwnedSlice() catch return error.OutOfMemory, .status = result.status };
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
